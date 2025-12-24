# Script PowerShell para executar o Spark Job no Windows

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Starting Spark Receivable Aggregator Job" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Configurar variáveis de ambiente para DynamoDB Local
$env:AWS_ACCESS_KEY_ID = "dummy"
$env:AWS_SECRET_ACCESS_KEY = "dummy"
$env:AWS_DEFAULT_REGION = "us-east-1"

# Verificar se o arquivo de configuração existe
$configPath = Join-Path $PSScriptRoot "config\application.json"
if (-not (Test-Path $configPath)) {
    Write-Host "❌ Configuration file not found: $configPath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Configuration file: $configPath" -ForegroundColor Green

# Pacotes Spark necessários
$sparkPackages = @(
    "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0",
    "org.elasticsearch:elasticsearch-spark-30_2.12:8.11.0"
)

Write-Host "✅ Spark packages: $($sparkPackages -join ', ')" -ForegroundColor Green
Write-Host ""

# Verificar se spark-submit está disponível
try {
    $sparkVersion = & spark-submit --version 2>&1 | Select-String "version"
    Write-Host "✅ Spark found: $sparkVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ spark-submit not found. Please install Apache Spark and add it to PATH" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🚀 Starting Spark Streaming Job..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Construir comando spark-submit
$jobPath = Join-Path $PSScriptRoot "src\receivable_aggregator.py"
$checkpointPath = "/tmp/spark-checkpoints"

$sparkArgs = @(
    "--packages", ($sparkPackages -join ','),
    "--conf", "spark.sql.streaming.checkpointLocation=$checkpointPath",
    "--conf", "spark.sql.shuffle.partitions=10",
    "--conf", "spark.driver.extraJavaOptions=-Dlog4j.configuration=file:log4j.properties",
    $jobPath
)

try {
    # Executar spark-submit
    & spark-submit @sparkArgs
    
    Write-Host ""
    Write-Host "✅ Spark job completed successfully" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "❌ Error executing Spark job: $_" -ForegroundColor Red
    exit 1
}
