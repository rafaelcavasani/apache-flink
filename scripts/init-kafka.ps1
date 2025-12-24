#!/usr/bin/env pwsh

Write-Host "⏳ Aguardando Kafka inicializar..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host "📨 Criando tópicos no Kafka..." -ForegroundColor Cyan

# Tópico para eventos de recebíveis agendados
Write-Host "`nCriando tópico 'recebiveis-agendados'..." -ForegroundColor Gray
docker exec kafka kafka-topics --create `
  --topic recebiveis-agendados `
  --bootstrap-server localhost:29092 `
  --partitions 3 `
  --replication-factor 1 `
  --config retention.ms=604800000 `
  --if-not-exists

if ($LASTEXITCODE -eq 0) {
  Write-Host "✅ Tópico 'recebiveis-agendados' criado (3 partições, 7 dias retenção)" -ForegroundColor Green
}

# Tópico para eventos de recebíveis cancelados
Write-Host "`nCriando tópico 'recebiveis-cancelados'..." -ForegroundColor Gray
docker exec kafka kafka-topics --create `
  --topic recebiveis-cancelados `
  --bootstrap-server localhost:29092 `
  --partitions 2 `
  --replication-factor 1 `
  --config retention.ms=2592000000 `
  --if-not-exists

if ($LASTEXITCODE -eq 0) {
  Write-Host "✅ Tópico 'recebiveis-cancelados' criado (2 partições, 30 dias retenção)" -ForegroundColor Green
}

# Tópico para eventos de recebíveis negociados
Write-Host "`nCriando tópico 'recebiveis-negociados'..." -ForegroundColor Gray
docker exec kafka kafka-topics --create `
  --topic recebiveis-negociados `
  --bootstrap-server localhost:29092 `
  --partitions 2 `
  --replication-factor 1 `
  --config retention.ms=2592000000 `
  --if-not-exists

if ($LASTEXITCODE -eq 0) {
  Write-Host "✅ Tópico 'recebiveis-negociados' criado (2 partições, 30 dias retenção)" -ForegroundColor Green
}

Write-Host "`n📋 Listando tópicos criados:" -ForegroundColor Cyan
docker exec kafka kafka-topics --list --bootstrap-server localhost:29092

Write-Host "`n📊 Detalhes dos tópicos:" -ForegroundColor Cyan
docker exec kafka kafka-topics --describe --bootstrap-server localhost:29092

Write-Host "`n🎉 Inicialização do Kafka concluída!" -ForegroundColor Green
