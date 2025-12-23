#!/bin/bash

echo "⏳ Aguardando DynamoDB Local inicializar..."
sleep 5

echo "📊 Criando tabela 'Recebiveis' no DynamoDB..."

aws dynamodb create-table \
  --table-name Recebiveis \
  --attribute-definitions \
      AttributeName=id_recebivel,AttributeType=S \
      AttributeName=codigo_cliente,AttributeType=S \
      AttributeName=data_vencimento,AttributeType=S \
  --key-schema \
      AttributeName=id_recebivel,KeyType=HASH \
  --global-secondary-indexes \
      "[
        {
          \"IndexName\": \"ClienteIndex\",
          \"KeySchema\": [{\"AttributeName\":\"codigo_cliente\",\"KeyType\":\"HASH\"}],
          \"Projection\": {\"ProjectionType\":\"ALL\"},
          \"ProvisionedThroughput\": {\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}
        },
        {
          \"IndexName\": \"ClienteVencimentoIndex\",
          \"KeySchema\": [
            {\"AttributeName\":\"codigo_cliente\",\"KeyType\":\"HASH\"},
            {\"AttributeName\":\"data_vencimento\",\"KeyType\":\"RANGE\"}
          ],
          \"Projection\": {\"ProjectionType\":\"ALL\"},
          \"ProvisionedThroughput\": {\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}
        }
      ]" \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --endpoint-url http://localhost:8000 \
  --region us-east-1 \
  --no-cli-pager

if [ $? -eq 0 ]; then
  echo "✅ Tabela 'Recebiveis' criada com sucesso!"
  echo "📋 Índices criados:"
  echo "   - ClienteIndex (GSI)"
  echo "   - ClienteVencimentoIndex (GSI composto)"
else
  echo "❌ Erro ao criar tabela 'Recebiveis'"
fi

echo ""
echo "📋 Listando tabelas existentes:"
aws dynamodb list-tables \
  --endpoint-url http://localhost:8000 \
  --region us-east-1 \
  --no-cli-pager

echo ""
echo "🎉 Inicialização do DynamoDB concluída!"
