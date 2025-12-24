#!/bin/bash
# Script para inicializar o Elasticsearch com o índice ciclo_vida_recebiveis
# Uso: ./init-elasticsearch.sh

set -e

echo "⏳ Aguardando Elasticsearch inicializar..."
sleep 5

# Verificar se o Elasticsearch está acessível
MAX_RETRIES=30
RETRY_COUNT=0
ES_READY=false

while [ "$ES_READY" = false ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s "http://localhost:9200/_cluster/health" | grep -q '"status":"green\|yellow"'; then
        ES_READY=true
        echo "✅ Elasticsearch está pronto!"
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "⏳ Aguardando Elasticsearch... tentativa $RETRY_COUNT/$MAX_RETRIES"
        sleep 2
    fi
done

if [ "$ES_READY" = false ]; then
    echo "❌ Erro: Elasticsearch não está acessível após $MAX_RETRIES tentativas"
    exit 1
fi

echo ""
echo "📊 Criando índice 'ciclo_vida_recebiveis' no Elasticsearch..."

# Verificar se o índice já existe e remover
if curl -s "http://localhost:9200/ciclo_vida_recebiveis" | grep -q "ciclo_vida_recebiveis"; then
    echo "⚠️  Índice 'ciclo_vida_recebiveis' já existe. Removendo..."
    curl -X DELETE "http://localhost:9200/ciclo_vida_recebiveis"
    echo "✅ Índice antigo removido"
fi

# Criar o índice com mapping
curl -X PUT "http://localhost:9200/ciclo_vida_recebiveis" \
-H "Content-Type: application/json" \
-d '{
  "mappings": {
    "properties": {
      "id_recebivel": {
        "type": "keyword"
      },
      "id_pagamento": {
        "type": "keyword"
      },
      "codigo_produto": {
        "type": "integer"
      },
      "codigo_produto_parceiro": {
        "type": "integer"
      },
      "modalidade": {
        "type": "integer"
      },
      "valor_original": {
        "type": "double"
      },
      "valor_disponivel": {
        "type": "double"
      },
      "valor_total_cancelado": {
        "type": "double"
      },
      "valor_total_negociado": {
        "type": "double"
      },
      "data_vencimento": {
        "type": "date",
        "format": "yyyy-MM-dd"
      },
      "cancelamentos": {
        "type": "nested",
        "properties": {
          "id_cancelamento": {
            "type": "keyword"
          },
          "data_cancelamento": {
            "type": "date",
            "format": "yyyy-MM-dd"
          },
          "valor_cancelado": {
            "type": "double"
          },
          "motivo": {
            "type": "text",
            "fields": {
              "keyword": {
                "type": "keyword",
                "ignore_above": 256
              }
            }
          }
        }
      },
      "negociacoes": {
        "type": "nested",
        "properties": {
          "id_negociacao": {
            "type": "keyword"
          },
          "data_negociacao": {
            "type": "date",
            "format": "yyyy-MM-dd"
          },
          "valor_negociado": {
            "type": "double"
          }
        }
      },
      "quantidade_cancelamentos": {
        "type": "integer"
      },
      "quantidade_negociacoes": {
        "type": "integer"
      },
      "quantidade_eventos": {
        "type": "integer"
      },
      "@timestamp": {
        "type": "date"
      },
      "window_start": {
        "type": "date"
      },
      "window_end": {
        "type": "date"
      }
    }
  },
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "refresh_interval": "5s"
  }
}'

echo ""
echo "✅ Índice 'ciclo_vida_recebiveis' criado com sucesso!"

echo ""
echo "📋 Informações do índice:"
curl -s "http://localhost:9200/ciclo_vida_recebiveis" | jq '{
  name: "ciclo_vida_recebiveis",
  shards: .ciclo_vida_recebiveis.settings.index.number_of_shards,
  replicas: .ciclo_vida_recebiveis.settings.index.number_of_replicas,
  fields: (.ciclo_vida_recebiveis.mappings.properties | keys | length)
}'

echo ""
echo "📌 Campos principais configurados:"
echo "  ✓ id_recebivel (keyword)"
echo "  ✓ id_pagamento (keyword)"
echo "  ✓ valor_original, valor_disponivel (double)"
echo "  ✓ data_vencimento (date)"
echo "  ✓ cancelamentos (nested)"
echo "  ✓ negociacoes (nested)"

echo ""
echo "🎉 Inicialização do Elasticsearch concluída!"
