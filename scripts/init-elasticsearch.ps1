# Script para inicializar o Elasticsearch com o índice ciclo_vida_recebiveis
# Uso: .\init-elasticsearch.ps1

Write-Host "⏳ Aguardando Elasticsearch inicializar..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Verificar se o Elasticsearch está acessível
$maxRetries = 30
$retryCount = 0
$esReady = $false

while (-not $esReady -and $retryCount -lt $maxRetries) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:9200/_cluster/health" -Method Get -ErrorAction Stop
        if ($response.status -in @("green", "yellow")) {
            $esReady = $true
            Write-Host "✅ Elasticsearch está pronto!" -ForegroundColor Green
        }
    }
    catch {
        $retryCount++
        Write-Host "⏳ Aguardando Elasticsearch... tentativa $retryCount/$maxRetries" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if (-not $esReady) {
    Write-Host "❌ Erro: Elasticsearch não está acessível após $maxRetries tentativas" -ForegroundColor Red
    exit 1
}

Write-Host "`n📊 Criando índice 'ciclo_vida_recebiveis' no Elasticsearch..." -ForegroundColor Cyan

# Definir o mapping do índice baseado na estrutura do ciclo_vida_recebivel.json
$mapping = @{
    mappings = @{
        properties = @{
            # Campos principais - Keywords para agregações exatas
            id_recebivel = @{
                type = "keyword"
            }
            id_pagamento = @{
                type = "keyword"
            }
            codigo_produto = @{
                type = "integer"
            }
            codigo_produto_parceiro = @{
                type = "integer"
            }
            modalidade = @{
                type = "integer"
            }
            
            # Campos de valores monetários
            valor_original = @{
                type = "double"
            }
            valor_disponivel = @{
                type = "double"
            }
            valor_total_cancelado = @{
                type = "double"
            }
            valor_total_negociado = @{
                type = "double"
            }
            
            # Datas
            data_vencimento = @{
                type = "date"
                format = "yyyy-MM-dd"
            }
            
            # Arrays de cancelamentos
            cancelamentos = @{
                type = "nested"
                properties = @{
                    id_cancelamento = @{
                        type = "keyword"
                    }
                    data_cancelamento = @{
                        type = "date"
                        format = "yyyy-MM-dd"
                    }
                    valor_cancelado = @{
                        type = "double"
                    }
                    motivo = @{
                        type = "text"
                        fields = @{
                            keyword = @{
                                type = "keyword"
                                ignore_above = 256
                            }
                        }
                    }
                }
            }
            
            # Arrays de negociações
            negociacoes = @{
                type = "nested"
                properties = @{
                    id_negociacao = @{
                        type = "keyword"
                    }
                    data_negociacao = @{
                        type = "date"
                        format = "yyyy-MM-dd"
                    }
                    valor_negociado = @{
                        type = "double"
                    }
                }
            }
            
            # Campos de metadados de agregação
            quantidade_cancelamentos = @{
                type = "integer"
            }
            quantidade_negociacoes = @{
                type = "integer"
            }
            quantidade_eventos = @{
                type = "integer"
            }
            
            # Timestamp da agregação
            "@timestamp" = @{
                type = "date"
            }
            window_start = @{
                type = "date"
            }
            window_end = @{
                type = "date"
            }
        }
    }
    settings = @{
        number_of_shards = 1
        number_of_replicas = 0
        refresh_interval = "5s"
    }
} | ConvertTo-Json -Depth 10

try {
    # Verificar se o índice já existe
    try {
        $existingIndex = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis" -Method Get -ErrorAction Stop
        Write-Host "⚠️  Índice 'ciclo_vida_recebiveis' já existe. Removendo..." -ForegroundColor Yellow
        Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis" -Method Delete | Out-Null
        Write-Host "✅ Índice antigo removido" -ForegroundColor Green
    }
    catch {
        # Índice não existe, tudo bem
    }

    # Criar o índice
    $response = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis" `
        -Method Put `
        -Body $mapping `
        -ContentType "application/json"
    
    Write-Host "✅ Índice 'ciclo_vida_recebiveis' criado com sucesso!" -ForegroundColor Green
    
    # Exibir informações do índice
    Write-Host "`n📋 Informações do índice:" -ForegroundColor Cyan
    $indexInfo = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis" -Method Get
    Write-Host "  - Nome: ciclo_vida_recebiveis" -ForegroundColor White
    Write-Host "  - Shards: $($indexInfo.'ciclo_vida_recebiveis'.settings.index.number_of_shards)" -ForegroundColor White
    Write-Host "  - Replicas: $($indexInfo.'ciclo_vida_recebiveis'.settings.index.number_of_replicas)" -ForegroundColor White
    Write-Host "  - Campos mapeados: $($indexInfo.'ciclo_vida_recebiveis'.mappings.properties.Count)" -ForegroundColor White
    
    # Listar alguns campos importantes
    Write-Host "`n📌 Campos principais configurados:" -ForegroundColor Cyan
    Write-Host "  ✓ id_recebivel (keyword)" -ForegroundColor Green
    Write-Host "  ✓ id_pagamento (keyword)" -ForegroundColor Green
    Write-Host "  ✓ valor_original, valor_disponivel (double)" -ForegroundColor Green
    Write-Host "  ✓ data_vencimento (date)" -ForegroundColor Green
    Write-Host "  ✓ cancelamentos (nested)" -ForegroundColor Green
    Write-Host "  ✓ negociacoes (nested)" -ForegroundColor Green
    
    Write-Host "`n🎉 Inicialização do Elasticsearch concluída!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Erro ao criar índice: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
