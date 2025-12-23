#!/bin/bash

echo "⏳ Aguardando Kafka inicializar..."
sleep 10

echo "📨 Criando tópicos no Kafka..."

# Tópico para eventos de recebíveis
docker exec kafka kafka-topics --create \
  --topic recebiveis-eventos \
  --bootstrap-server localhost:29092 \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-eventos' criado (3 partições, 7 dias retenção)"
fi

# Tópico para cancelamentos
docker exec kafka kafka-topics --create \
  --topic recebiveis-cancelamentos \
  --bootstrap-server localhost:29092 \
  --partitions 2 \
  --replication-factor 1 \
  --config retention.ms=2592000000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-cancelamentos' criado (2 partições, 30 dias retenção)"
fi

# Tópico para negociações
docker exec kafka kafka-topics --create \
  --topic recebiveis-negociacoes \
  --bootstrap-server localhost:29092 \
  --partitions 2 \
  --replication-factor 1 \
  --config retention.ms=2592000000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-negociacoes' criado (2 partições, 30 dias retenção)"
fi

# Tópico para agregações (output do Flink)
docker exec kafka kafka-topics --create \
  --topic recebiveis-agregados \
  --bootstrap-server localhost:29092 \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=86400000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-agregados' criado (3 partições, 24h retenção)"
fi

echo ""
echo "📋 Listando tópicos criados:"
docker exec kafka kafka-topics --list --bootstrap-server localhost:29092

echo ""
echo "📊 Detalhes dos tópicos:"
docker exec kafka kafka-topics --describe --bootstrap-server localhost:29092

echo ""
echo "🎉 Inicialização do Kafka concluída!"
