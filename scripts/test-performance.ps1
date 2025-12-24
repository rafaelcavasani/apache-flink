#!/usr/bin/env pwsh
# Script de teste de performance para o Flink Aggregator

param(
    [int]$EventCount = 10000,
    [int]$Workers = 20,
    [int]$IntervalMs = 10,
    [int]$WindowSeconds = 15
)

Write-Host "🚀 Teste de Performance - Flink Aggregator" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuração:" -ForegroundColor Yellow
Write-Host "  📊 Eventos a enviar: $EventCount"
Write-Host "  👷 Workers: $Workers"
Write-Host "  ⏱️  Intervalo: ${IntervalMs}ms"
Write-Host "  🪟 Janela de agregação: ${WindowSeconds}s"
Write-Host ""

# Limpar índice do Elasticsearch
Write-Host "🧹 Limpando índice anterior..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis" -Method Delete -ErrorAction SilentlyContinue
    Write-Host "✅ Índice limpo" -ForegroundColor Green
} catch {
    Write-Host "ℹ️  Índice não existe ou já está vazio" -ForegroundColor Gray
}
Start-Sleep -Seconds 2

# Recriar índice
Write-Host "📝 Recriando índice..." -ForegroundColor Yellow
& ".\scripts\init-elasticsearch.ps1"
Start-Sleep -Seconds 2

# Verificar se o job está rodando
Write-Host "🔍 Verificando status do Flink job..." -ForegroundColor Yellow
$jobStatus = docker exec flink-jobmanager flink list 2>&1 | Select-String "running"
if ($jobStatus) {
    Write-Host "✅ Job está rodando" -ForegroundColor Green
} else {
    Write-Host "⚠️  Nenhum job em execução - inicie o job primeiro!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Marcar tempo de início
$startTime = Get-Date
Write-Host "⏰ Início do teste: $($startTime.ToString('HH:mm:ss'))" -ForegroundColor Cyan
Write-Host ""

# Enviar eventos
Write-Host "📤 Enviando $EventCount eventos..." -ForegroundColor Yellow
Set-Location -Path ".\producer"
$producerStart = Get-Date
go run main.go -count $EventCount -interval "${IntervalMs}ms" 2>&1 | Tee-Object -Variable producerOutput
$producerEnd = Get-Date
Set-Location -Path ".."

$producerDuration = ($producerEnd - $producerStart).TotalSeconds
$eventsPerSecond = [math]::Round($EventCount / $producerDuration, 2)

Write-Host ""
Write-Host "✅ Envio concluído em $([math]::Round($producerDuration, 2))s" -ForegroundColor Green
Write-Host "📊 Taxa de envio: $eventsPerSecond eventos/s" -ForegroundColor Cyan
Write-Host ""

# Aguardar processamento das janelas
$waitTime = $WindowSeconds + 5
Write-Host "⏳ Aguardando ${waitTime}s para processamento das janelas..." -ForegroundColor Yellow
Start-Sleep -Seconds $waitTime

# Verificar agregações
Write-Host ""
Write-Host "📈 Coletando métricas de agregação..." -ForegroundColor Yellow

$countResponse = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_count" -Method Get
$aggregationCount = $countResponse.count

$endTime = Get-Date
$totalDuration = ($endTime - $startTime).TotalSeconds

# Calcular métricas
$eventsProcessedPerSecond = [math]::Round($EventCount / $totalDuration, 2)
$aggregationsPerSecond = [math]::Round($aggregationCount / $totalDuration, 2)

# Buscar estatísticas detalhadas
$statsQuery = @{
    size = 0
    aggs = @{
        total_valor_disponivel = @{ sum = @{ field = "valor_disponivel" } }
        total_cancelado = @{ sum = @{ field = "valor_total_cancelado" } }
        total_negociado = @{ sum = @{ field = "valor_total_negociado" } }
        avg_eventos = @{ avg = @{ field = "quantidade_eventos" } }
        unique_pagamentos = @{ cardinality = @{ field = "id_pagamento.keyword" } }
    }
} | ConvertTo-Json -Depth 10

$statsResponse = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_search" -Method Post -Body $statsQuery -ContentType "application/json"

# Exibir resultados
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "📊 RESULTADOS DO TESTE DE PERFORMANCE" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Envio de Eventos:" -ForegroundColor Yellow
Write-Host "  ⏱️  Duração do envio: $([math]::Round($producerDuration, 2))s"
Write-Host "  📤 Taxa de envio: $eventsPerSecond eventos/s"
Write-Host ""
Write-Host "Processamento Completo:" -ForegroundColor Yellow
Write-Host "  ⏱️  Duração total: $([math]::Round($totalDuration, 2))s"
Write-Host "  📥 Eventos processados: $EventCount"
Write-Host "  📊 Agregações criadas: $aggregationCount"
Write-Host "  🚀 Taxa de processamento: $eventsProcessedPerSecond eventos/s"
Write-Host "  📈 Taxa de agregação: $aggregationsPerSecond agregações/s"
Write-Host ""
Write-Host "Estatísticas das Agregações:" -ForegroundColor Yellow
Write-Host "  💰 Total Valor Disponível: R$ $([math]::Round($statsResponse.aggregations.total_valor_disponivel.value, 2))"
Write-Host "  ❌ Total Cancelado: R$ $([math]::Round($statsResponse.aggregations.total_cancelado.value, 2))"
Write-Host "  🤝 Total Negociado: R$ $([math]::Round($statsResponse.aggregations.total_negociado.value, 2))"
Write-Host "  📊 Média de Eventos/Agregação: $([math]::Round($statsResponse.aggregations.avg_eventos.value, 2))"
Write-Host "  💳 Pagamentos Únicos: $($statsResponse.aggregations.unique_pagamentos.value)"
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "✅ Teste concluído!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan

# Salvar resultados em arquivo
$results = @{
    test_time = $startTime.ToString("yyyy-MM-dd HH:mm:ss")
    config = @{
        event_count = $EventCount
        workers = $Workers
        interval_ms = $IntervalMs
        window_seconds = $WindowSeconds
    }
    metrics = @{
        producer_duration_seconds = [math]::Round($producerDuration, 2)
        total_duration_seconds = [math]::Round($totalDuration, 2)
        events_sent = $EventCount
        aggregations_created = $aggregationCount
        send_rate_events_per_sec = $eventsPerSecond
        processing_rate_events_per_sec = $eventsProcessedPerSecond
        aggregation_rate_per_sec = $aggregationsPerSecond
        avg_events_per_aggregation = [math]::Round($statsResponse.aggregations.avg_eventos.value, 2)
        unique_payments = $statsResponse.aggregations.unique_pagamentos.value
    }
}

$resultsJson = $results | ConvertTo-Json -Depth 10
$resultsFile = ".\performance_test\performance_test_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$resultsJson | Out-File -FilePath $resultsFile -Encoding utf8
Write-Host "📁 Resultados salvos em: $resultsFile" -ForegroundColor Cyan
