#!/usr/bin/env pwsh
# Script de validação de consistência entre DynamoDB e Elasticsearch

param(
    [string[]]$ReceivableIds = @()
)

Write-Host "🔍 VALIDAÇÃO DE CONSISTÊNCIA DE DADOS" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Se não foram fornecidos IDs, buscar do Elasticsearch
if ($ReceivableIds.Count -eq 0) {
    Write-Host "📊 Buscando IDs do Elasticsearch..." -ForegroundColor Yellow
    $esResponse = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_search?size=50" -Method Get
    $ReceivableIds = $esResponse.hits.hits | ForEach-Object { $_._id }
    Write-Host "✅ Encontrados $($ReceivableIds.Count) IDs para validar" -ForegroundColor Green
    Write-Host ""
}

$validationResults = @()
$successCount = 0
$errorCount = 0

foreach ($id in $ReceivableIds) {
    Write-Host "🔎 Validando: $id" -ForegroundColor White
    
    $result = @{
        id_recebivel = $id
        elasticsearch_exists = $false
        dynamodb_events = 0
        consistency_check = "PENDING"
        errors = @()
        details = @{}
    }
    
    try {
        # 1. Buscar dados no Elasticsearch
        Write-Host "  📥 Consultando Elasticsearch..." -ForegroundColor Gray
        $esDoc = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_doc/$id" -Method Get -ErrorAction Stop
        $result.elasticsearch_exists = $true
        $esData = $esDoc._source
        
        Write-Host "  ✅ Elasticsearch: Encontrado" -ForegroundColor Green
        Write-Host "     💰 Valor Original: R$ $($esData.valor_original)" -ForegroundColor Gray
        Write-Host "     💵 Valor Disponível: R$ $([math]::Round($esData.valor_disponivel, 2))" -ForegroundColor Gray
        Write-Host "     📊 Eventos: $($esData.quantidade_eventos)" -ForegroundColor Gray
        Write-Host "     ❌ Cancelamentos: $($esData.quantidade_cancelamentos)" -ForegroundColor Gray
        Write-Host "     🤝 Negociações: $($esData.quantidade_negociacoes)" -ForegroundColor Gray
        
        # 2. Buscar eventos no DynamoDB
        Write-Host "  📥 Consultando DynamoDB..." -ForegroundColor Gray
        $dynamoQuery = @{
            TableName = "Recebiveis"
            KeyConditionExpression = "id_recebivel = :id"
            ExpressionAttributeValues = @{
                ":id" = @{ S = $id }
            }
        } | ConvertTo-Json -Depth 10 -Compress
        
        $dynamoResponse = aws dynamodb query --table-name Recebiveis --key-condition-expression "id_recebivel = :id" --expression-attribute-values "{`":id`":{`"S`":`"$id`"}}" --endpoint-url http://localhost:8000 --no-cli-pager | ConvertFrom-Json
        
        $dynamoEvents = $dynamoResponse.Items
        $result.dynamodb_events = $dynamoEvents.Count
        
        Write-Host "  ✅ DynamoDB: $($dynamoEvents.Count) eventos encontrados" -ForegroundColor Green
        
        if ($dynamoEvents.Count -eq 0) {
            $result.errors += "Nenhum evento encontrado no DynamoDB"
            $result.consistency_check = "ERROR"
            $errorCount++
            Write-Host "  ❌ ERRO: Sem eventos no DynamoDB!" -ForegroundColor Red
            continue
        }
        
        # 3. Validar consistência
        Write-Host "  🔍 Validando consistência..." -ForegroundColor Gray
        
        # Contar eventos por tipo no DynamoDB
        $agendadoEvents = $dynamoEvents | Where-Object { $_.tipo_evento.S -eq "agendado" }
        $canceladoEvents = $dynamoEvents | Where-Object { $_.tipo_evento.S -eq "cancelado" }
        $negociadoEvents = $dynamoEvents | Where-Object { $_.tipo_evento.S -eq "negociado" }
        
        $result.details = @{
            es_quantidade_eventos = $esData.quantidade_eventos
            dynamo_total_eventos = $dynamoEvents.Count
            es_quantidade_cancelamentos = $esData.quantidade_cancelamentos
            dynamo_cancelamentos = $canceladoEvents.Count
            es_quantidade_negociacoes = $esData.quantidade_negociacoes
            dynamo_negociacoes = $negociadoEvents.Count
        }
        
        # Validação 1: Total de eventos
        if ($esData.quantidade_eventos -ne $dynamoEvents.Count) {
            $result.errors += "Divergência no total de eventos: ES=$($esData.quantidade_eventos) vs DynamoDB=$($dynamoEvents.Count)"
        }
        
        # Validação 2: Quantidade de cancelamentos
        if ($esData.quantidade_cancelamentos -ne $canceladoEvents.Count) {
            $result.errors += "Divergência em cancelamentos: ES=$($esData.quantidade_cancelamentos) vs DynamoDB=$($canceladoEvents.Count)"
        }
        
        # Validação 3: Quantidade de negociações
        if ($esData.quantidade_negociacoes -ne $negociadoEvents.Count) {
            $result.errors += "Divergência em negociações: ES=$($esData.quantidade_negociacoes) vs DynamoDB=$($negociadoEvents.Count)"
        }
        
        # Validação 4: Valor original
        if ($agendadoEvents.Count -gt 0) {
            $dynamoValorOriginal = if ($agendadoEvents[0].valor_original.N) {
                [double]$agendadoEvents[0].valor_original.N
            } elseif ($agendadoEvents[0].valor_original.S) {
                [double]$agendadoEvents[0].valor_original.S
            } else { 0 }
            
            if ($esData.valor_original -ne $dynamoValorOriginal) {
                $result.errors += "Divergência no valor original: ES=$($esData.valor_original) vs DynamoDB=$dynamoValorOriginal"
            }
        }
        
        # Validação 5: Soma de cancelamentos
        if ($canceladoEvents.Count -gt 0) {
            $dynamoTotalCancelado = ($canceladoEvents | ForEach-Object { 
                if ($_.valor_cancelado -and $_.valor_cancelado.N) {
                    [double]$_.valor_cancelado.N 
                } elseif ($_.valor_cancelado -and $_.valor_cancelado.S) {
                    [double]$_.valor_cancelado.S
                } else { 
                    0 
                }
            } | Measure-Object -Sum).Sum
            
            $esTotalCancelado = if ($esData.valor_total_cancelado) { $esData.valor_total_cancelado } else { 0 }
            
            if ([math]::Abs($esTotalCancelado - $dynamoTotalCancelado) -gt 0.01) {
                $result.errors += "Divergência no total cancelado: ES=$([math]::Round($esTotalCancelado, 2)) vs DynamoDB=$([math]::Round($dynamoTotalCancelado, 2))"
            }
        }
        
        # Validação 6: Soma de negociações
        if ($negociadoEvents.Count -gt 0) {
            $dynamoTotalNegociado = ($negociadoEvents | ForEach-Object { 
                if ($_.valor_negociado -and $_.valor_negociado.N) {
                    [double]$_.valor_negociado.N 
                } elseif ($_.valor_negociado -and $_.valor_negociado.S) {
                    [double]$_.valor_negociado.S
                } else { 
                    0 
                }
            } | Measure-Object -Sum).Sum
            
            $esTotalNegociado = if ($esData.valor_total_negociado) { $esData.valor_total_negociado } else { 0 }
            
            if ([math]::Abs($esTotalNegociado - $dynamoTotalNegociado) -gt 0.01) {
                $result.errors += "Divergência no total negociado: ES=$([math]::Round($esTotalNegociado, 2)) vs DynamoDB=$([math]::Round($dynamoTotalNegociado, 2))"
            }
        }
        
        # Validação 7: Arrays de cancelamentos e negociações
        $esCancelamentosCount = if ($esData.cancelamentos) { $esData.cancelamentos.Count } else { 0 }
        if ($esCancelamentosCount -ne $canceladoEvents.Count) {
            $result.errors += "Divergência no array de cancelamentos: ES=$esCancelamentosCount itens vs DynamoDB=$($canceladoEvents.Count) eventos"
        }
        
        $esNegociacoesCount = if ($esData.negociacoes) { $esData.negociacoes.Count } else { 0 }
        if ($esNegociacoesCount -ne $negociadoEvents.Count) {
            $result.errors += "Divergência no array de negociações: ES=$esNegociacoesCount itens vs DynamoDB=$($negociadoEvents.Count) eventos"
        }
        
        # Resultado final
        if ($result.errors.Count -eq 0) {
            $result.consistency_check = "OK"
            $successCount++
            Write-Host "  ✅ VALIDAÇÃO OK!" -ForegroundColor Green
        } else {
            $result.consistency_check = "ERROR"
            $errorCount++
            Write-Host "  ❌ ERROS ENCONTRADOS:" -ForegroundColor Red
            foreach ($validationError in $result.errors) {
                Write-Host "     • $validationError" -ForegroundColor Red
            }
        }
        
    } catch {
        $result.consistency_check = "ERROR"
        $exceptionMsg = $_.Exception.Message
        $result.errors += $exceptionMsg
        $errorCount++
        Write-Host "  ❌ ERRO: $exceptionMsg" -ForegroundColor Red
    }
    
    $validationResults += $result
    Write-Host ""
}

# Resumo final
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "📊 RESUMO DA VALIDAÇÃO" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total de IDs validados: $($ReceivableIds.Count)" -ForegroundColor White
Write-Host "✅ Validações OK: $successCount" -ForegroundColor Green
Write-Host "❌ Validações com erro: $errorCount" -ForegroundColor Red
Write-Host ""

if ($errorCount -gt 0) {
    Write-Host "🔍 Detalhes dos erros:" -ForegroundColor Yellow
    foreach ($result in $validationResults | Where-Object { $_.consistency_check -eq "ERROR" }) {
        Write-Host ""
        Write-Host "  ID: $($result.id_recebivel)" -ForegroundColor White
        foreach ($validationError in $result.errors) {
            Write-Host "    • $validationError" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan

# Salvar resultados
$outputFile = ".\performance_test\validation_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$validationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding utf8
Write-Host "📁 Resultados salvos em: $outputFile" -ForegroundColor Cyan

# Retornar código de saída
if ($errorCount -eq 0) {
    exit 0
} else {
    exit 1
}
