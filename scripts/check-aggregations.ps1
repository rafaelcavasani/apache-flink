# Script para verificar agregações no índice ciclo_vida_recebiveis
# Uso: .\check-aggregations.ps1

Write-Host "🔍 Verificando agregações no Elasticsearch..." -ForegroundColor Cyan

# Contar documentos no índice
try {
    $count = (Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_count" -Method Get).count
    Write-Host "📊 Total de agregações: $count" -ForegroundColor Green
    
    if ($count -eq 0) {
        Write-Host "⚠️  Nenhuma agregação encontrada ainda." -ForegroundColor Yellow
        Write-Host "   As agregações são criadas após o fechamento das janelas de 5 minutos." -ForegroundColor White
        Write-Host "   Aguarde alguns minutos e execute novamente." -ForegroundColor White
        exit 0
    }
    
    # Buscar primeiras agregações
    Write-Host "`n📋 Primeiras agregações (top 10):" -ForegroundColor Cyan
    $response = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_search?size=10&sort=@timestamp:desc" -Method Get
    
    foreach ($hit in $response.hits.hits) {
        $doc = $hit._source
        Write-Host "`n  🆔 ID Recebível: $($doc.id_recebivel)" -ForegroundColor White
        Write-Host "     ID Pagamento: $($doc.id_pagamento)" -ForegroundColor Gray
        
        if ($doc.valor_original) {
            Write-Host "     💰 Valor Original: R$ $($doc.valor_original)" -ForegroundColor Gray
        }
        if ($doc.valor_disponivel) {
            Write-Host "     💵 Valor Disponível: R$ $($doc.valor_disponivel)" -ForegroundColor Gray
        }
        if ($doc.valor_total_cancelado) {
            Write-Host "     ❌ Total Cancelado: R$ $($doc.valor_total_cancelado)" -ForegroundColor Gray
        }
        if ($doc.valor_total_negociado) {
            Write-Host "     🤝 Total Negociado: R$ $($doc.valor_total_negociado)" -ForegroundColor Gray
        }
        
        if ($doc.quantidade_eventos) {
            Write-Host "     📊 Quantidade de Eventos: $($doc.quantidade_eventos)" -ForegroundColor Gray
        }
        if ($doc.quantidade_cancelamentos) {
            Write-Host "     📊 Cancelamentos: $($doc.quantidade_cancelamentos)" -ForegroundColor Gray
        }
        if ($doc.quantidade_negociacoes) {
            Write-Host "     📊 Negociações: $($doc.quantidade_negociacoes)" -ForegroundColor Gray
        }
        
        if ($doc.'@timestamp') {
            Write-Host "     ⏰ Timestamp: $($doc.'@timestamp')" -ForegroundColor Gray
        }
    }
    
    # Estatísticas agregadas
    Write-Host "`n📈 Estatísticas Gerais:" -ForegroundColor Cyan
    
    $stats = Invoke-RestMethod -Uri "http://localhost:9200/ciclo_vida_recebiveis/_search?size=0" -Method Post -Body '{
      "aggs": {
        "total_valor_disponivel": {
          "sum": {
            "field": "valor_disponivel"
          }
        },
        "total_cancelado": {
          "sum": {
            "field": "valor_total_cancelado"
          }
        },
        "total_negociado": {
          "sum": {
            "field": "valor_total_negociado"
          }
        },
        "media_valor_disponivel": {
          "avg": {
            "field": "valor_disponivel"
          }
        },
        "recebiveis_unicos": {
          "cardinality": {
            "field": "id_recebivel"
          }
        },
        "pagamentos_unicos": {
          "cardinality": {
            "field": "id_pagamento"
          }
        }
      }
    }' -ContentType "application/json"
    
    Write-Host "  💰 Total Valor Disponível: R$ $([math]::Round($stats.aggregations.total_valor_disponivel.value, 2))" -ForegroundColor White
    Write-Host "  ❌ Total Cancelado: R$ $([math]::Round($stats.aggregations.total_cancelado.value, 2))" -ForegroundColor White
    Write-Host "  🤝 Total Negociado: R$ $([math]::Round($stats.aggregations.total_negociado.value, 2))" -ForegroundColor White
    Write-Host "  📊 Média Valor Disponível: R$ $([math]::Round($stats.aggregations.media_valor_disponivel.value, 2))" -ForegroundColor White
    Write-Host "  🆔 Recebíveis Únicos: $($stats.aggregations.recebiveis_unicos.value)" -ForegroundColor White
    Write-Host "  💳 Pagamentos Únicos: $($stats.aggregations.pagamentos_unicos.value)" -ForegroundColor White
    
    Write-Host "`n✅ Verificação concluída!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Erro ao acessar Elasticsearch: $_" -ForegroundColor Red
    if ($_.Exception.Message -like "*404*") {
        Write-Host "   O índice 'ciclo_vida_recebiveis' ainda não foi criado." -ForegroundColor Yellow
        Write-Host "   Execute: .\scripts\init-elasticsearch.ps1" -ForegroundColor White
    }
}
