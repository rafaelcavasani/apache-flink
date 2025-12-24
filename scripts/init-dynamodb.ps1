#!/usr/bin/env pwsh

Write-Host "⏳ Aguardando DynamoDB Local inicializar..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host "📊 Criando tabela 'Recebiveis' no DynamoDB..." -ForegroundColor Cyan

aws dynamodb create-table `
  --table-name Recebiveis `
  --attribute-definitions `
      AttributeName=id_recebivel,AttributeType=S `
      AttributeName=tipo_evento,AttributeType=S `
  --key-schema `
      AttributeName=id_recebivel,KeyType=HASH `
      AttributeName=tipo_evento,KeyType=RANGE `
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 `
  --endpoint-url http://localhost:8000 `
  --region us-east-1 `
  --no-cli-pager

if ($LASTEXITCODE -eq 0) {
  Write-Host "✅ Tabela 'Recebiveis' criada com sucesso!" -ForegroundColor Green
} else {
  Write-Host "❌ Erro ao criar tabela 'Recebiveis'" -ForegroundColor Red
}

Write-Host "`n📋 Listando tabelas existentes:" -ForegroundColor Cyan
aws dynamodb list-tables `
  --endpoint-url http://localhost:8000 `
  --region us-east-1 `
  --no-cli-pager

Write-Host "`n🎉 Inicialização do DynamoDB concluída!" -ForegroundColor Green
