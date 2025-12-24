#!/bin/bash

echo "⏳ Aguardando Kafka inicializar..."
sleep 10

echo "📨 Criando tópicos no Kafka..."

# Tópico para eventos de recebíveis agendados
docker exec kafka kafka-topics --create \
  --topic recebiveis-agendados \
  --bootstrap-server localhost:29092 \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=604800000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-agendados' criado (3 partições, 7 dias retenção)"
fi

# Tópico para eventos de recebíveis cancelados
docker exec kafka kafka-topics --create \
  --topic recebiveis-cancelados \
  --bootstrap-server localhost:29092 \
  --partitions 2 \
  --replication-factor 1 \
  --config retention.ms=2592000000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-cancelados' criado (2 partições, 30 dias retenção)"
fi

# Tópico para eventos de recebíveis negociados
docker exec kafka kafka-topics --create \
  --topic recebiveis-negociados \
  --bootstrap-server localhost:29092 \
  --partitions 2 \
  --replication-factor 1 \
  --config retention.ms=2592000000 \
  --if-not-exists

if [ $? -eq 0 ]; then
  echo "✅ Tópico 'recebiveis-negociados' criado (2 partições, 30 dias retenção)"
fi

echo ""
echo "📋 Listando tópicos criados:"
docker exec kafka kafka-topics --list --bootstrap-server localhost:29092

echo ""
echo "📊 Detalhes dos tópicos:"
docker exec kafka kafka-topics --describe --bootstrap-server localhost:29092

echo ""
echo "🎉 Inicialização do Kafka concluída!"
