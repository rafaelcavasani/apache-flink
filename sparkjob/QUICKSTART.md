# Guia de Início Rápido - Spark Job

## Instalação Rápida

### 1. Instalar Python e Dependências

```bash
# Verificar Python
python --version  # Deve ser 3.8+

# Instalar dependências
pip install -r requirements.txt
```

### 2. Instalar Apache Spark

**Windows:**
```powershell
# Baixar Spark 3.5.0
# https://spark.apache.org/downloads.html

# Extrair para C:\spark
# Adicionar ao PATH:
$env:SPARK_HOME = "C:\spark"
$env:PATH += ";C:\spark\bin"
```

**Linux/Mac:**
```bash
# Baixar e extrair
wget https://dlcdn.apache.org/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz
tar -xzf spark-3.5.0-bin-hadoop3.tgz
sudo mv spark-3.5.0-bin-hadoop3 /opt/spark

# Adicionar ao PATH
export SPARK_HOME=/opt/spark
export PATH=$PATH:$SPARK_HOME/bin
```

### 3. Configurar AWS Credentials (para DynamoDB Local)

```bash
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=us-east-1
```

## Executar

### Testar Conexões

```bash
python test.py
```

### Executar Job

**Windows:**
```powershell
.\run.ps1
```

**Linux/Mac:**
```bash
chmod +x run.sh
./run.sh
```

**Ou com Python:**
```bash
python run.py
```

## Verificar Resultados

### Elasticsearch
```bash
curl http://localhost:9200/ciclo_vida_recebiveis/_search?pretty
```

### DynamoDB
```bash
aws dynamodb scan --table-name Recebiveis --endpoint-url http://localhost:8000
```

## Monitoramento

- **Spark UI**: http://localhost:4040
- **Logs**: Console output

## Solução de Problemas

### Spark não encontrado
```bash
# Verificar instalação
spark-submit --version

# Se não funcionar, adicionar ao PATH
export PATH=$PATH:/opt/spark/bin
```

### Erro de conexão com Kafka
```bash
# Verificar Kafka rodando
docker ps | grep kafka

# Ou iniciar Kafka
docker-compose up -d kafka
```

### Erro no DynamoDB
```bash
# Verificar DynamoDB Local rodando
aws dynamodb list-tables --endpoint-url http://localhost:8000

# Criar tabela se necessário
cd ../scripts
./init-dynamodb.ps1
```

## Parar o Job

Pressione `Ctrl+C` no terminal onde o job está rodando.

## Próximos Passos

1. Executar o producer Go para gerar eventos:
   ```bash
   cd ../producer
   go run main.go -count 100
   ```

2. Monitorar o processamento no Spark UI

3. Validar resultados:
   ```bash
   cd ../scripts
   .\validate-data-consistency.ps1
   ```
