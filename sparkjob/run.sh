#!/bin/bash
# Script bash para executar o Spark Job no Linux/Mac

echo "============================================================"
echo "Starting Spark Receivable Aggregator Job"
echo "============================================================"
echo ""

# Configurar variáveis de ambiente para DynamoDB Local
export AWS_ACCESS_KEY_ID="dummy"
export AWS_SECRET_ACCESS_KEY="dummy"
export AWS_DEFAULT_REGION="us-east-1"

# Diretório do script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_PATH="$SCRIPT_DIR/config/application.json"

# Verificar se o arquivo de configuração existe
if [ ! -f "$CONFIG_PATH" ]; then
    echo "❌ Configuration file not found: $CONFIG_PATH"
    exit 1
fi

echo "✅ Configuration file: $CONFIG_PATH"

# Pacotes Spark necessários
SPARK_PACKAGES="org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.elasticsearch:elasticsearch-spark-30_2.12:8.11.0"

echo "✅ Spark packages: $SPARK_PACKAGES"
echo ""

# Verificar se spark-submit está disponível
if ! command -v spark-submit &> /dev/null; then
    echo "❌ spark-submit not found. Please install Apache Spark and add it to PATH"
    exit 1
fi

SPARK_VERSION=$(spark-submit --version 2>&1 | grep "version" | head -n 1)
echo "✅ Spark found: $SPARK_VERSION"

echo ""
echo "🚀 Starting Spark Streaming Job..."
echo "============================================================"
echo ""

# Caminho do job
JOB_PATH="$SCRIPT_DIR/src/receivable_aggregator.py"
CHECKPOINT_PATH="/tmp/spark-checkpoints"

# Executar spark-submit
spark-submit \
  --packages "$SPARK_PACKAGES" \
  --conf "spark.sql.streaming.checkpointLocation=$CHECKPOINT_PATH" \
  --conf "spark.sql.shuffle.partitions=10" \
  "$JOB_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Spark job completed successfully"
else
    echo ""
    echo "❌ Error executing Spark job"
    exit 1
fi
