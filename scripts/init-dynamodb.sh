#!/bin/bash

echo "⏳ Aguardando DynamoDB Local inicializar..."
sleep 5

echo "📊 Criando tabela 'Recebiveis' no DynamoDB..."

aws dynamodb create-table \
  --table-name Recebiveis \
  --attribute-definitions \
      AttributeName=id_recebivel,AttributeType=S \
      AttributeName=tipo_evento,AttributeType=S \
  --key-schema \
      AttributeName=id_recebivel,KeyType=HASH \
      AttributeName=tipo_evento,KeyType=RANGE \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --endpoint-url http://localhost:8000 \
  --region us-east-1 \
  --no-cli-pager

if [ $? -eq 0 ]; then
  echo "✅ Tabela 'Recebiveis' criada com sucesso!"
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
