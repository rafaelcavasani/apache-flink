# Exemplos de Uso - Spark Job

## Exemplo 1: Execução Básica

```bash
# 1. Iniciar serviços (se ainda não estiverem rodando)
cd ../
docker-compose up -d kafka dynamodb elasticsearch

# 2. Criar tabela DynamoDB
cd scripts
./init-dynamodb.ps1

# 3. Criar índice Elasticsearch
./init-elasticsearch.ps1

# 4. Executar o job Spark
cd ../sparkjob
python run.py

# 5. Em outro terminal, executar o producer
cd ../producer
go run main.go -count 100 -interval 10ms
```

## Exemplo 2: Monitoramento em Tempo Real

```bash
# Terminal 1: Job Spark
cd sparkjob
python run.py

# Terminal 2: Producer contínuo
cd ../producer
while true; do
    go run main.go -count 50 -interval 20ms
    sleep 5
done

# Terminal 3: Monitorar Elasticsearch
watch -n 2 'curl -s http://localhost:9200/ciclo_vida_recebiveis/_count | jq'

# Terminal 4: Monitorar DynamoDB
watch -n 2 'aws dynamodb scan --table-name Recebiveis --endpoint-url http://localhost:8000 --select COUNT | jq'
```

## Exemplo 3: Validação de Dados

```bash
# Executar producer
cd producer
go run main.go -count 200

# Aguardar processamento (30 segundos)
sleep 30

# Validar consistência
cd ../scripts
./validate-data-consistency.ps1
```

## Exemplo 4: Teste de Performance

```bash
# 1. Limpar dados anteriores
curl -X DELETE http://localhost:9200/ciclo_vida_recebiveis
cd scripts
./init-elasticsearch.ps1

# 2. Iniciar job Spark
cd ../sparkjob
python run.py &
SPARK_PID=$!

# 3. Executar teste de 2 minutos
cd ../producer
go run main.go -count 1000 -interval 5ms

# 4. Aguardar processamento
sleep 60

# 5. Validar resultados
cd ../scripts
./validate-data-consistency.ps1

# 6. Parar job Spark
kill $SPARK_PID
```

## Exemplo 5: Consultas no Elasticsearch

### Buscar todos os recebíveis
```bash
curl -X GET "http://localhost:9200/ciclo_vida_recebiveis/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": { "match_all": {} },
    "size": 10
  }'
```

### Buscar recebível específico
```bash
ID="seu-id-aqui"
curl -X GET "http://localhost:9200/ciclo_vida_recebiveis/_doc/$ID?pretty"
```

### Buscar recebíveis com valor disponível negativo
```bash
curl -X GET "http://localhost:9200/ciclo_vida_recebiveis/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "valor_disponivel": { "lt": 0 }
      }
    }
  }'
```

### Buscar recebíveis com cancelamentos
```bash
curl -X GET "http://localhost:9200/ciclo_vida_recebiveis/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "quantidade_cancelamentos": { "gt": 0 }
      }
    }
  }'
```

### Agregação: soma de valores originais
```bash
curl -X GET "http://localhost:9200/ciclo_vida_recebiveis/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "total_valor_original": {
        "sum": { "field": "valor_original" }
      }
    }
  }'
```

## Exemplo 6: Consultas no DynamoDB

### Listar todos os eventos
```bash
aws dynamodb scan \
  --table-name Recebiveis \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

### Buscar eventos de um recebível específico
```bash
ID="seu-id-aqui"
aws dynamodb query \
  --table-name Recebiveis \
  --key-condition-expression "id_recebivel = :id" \
  --expression-attribute-values '{":id":{"S":"'$ID'"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

### Contar total de eventos
```bash
aws dynamodb scan \
  --table-name Recebiveis \
  --select COUNT \
  --endpoint-url http://localhost:8000 \
  --region us-east-1 | jq '.Count'
```

## Exemplo 7: Debug e Troubleshooting

### Ver logs do Spark com mais detalhe
```python
# Modificar receivable_aggregator.py temporariamente
spark.sparkContext.setLogLevel("INFO")  # ou "DEBUG"
```

### Testar conexões antes de rodar
```bash
python test.py
```

### Verificar checkpoint
```bash
ls -la /tmp/spark-checkpoints/
```

### Limpar checkpoint para restart limpo
```bash
rm -rf /tmp/spark-checkpoints/*
```

## Exemplo 8: Customização

### Alterar tamanho da janela para 30 segundos

Editar `config/application.json`:
```json
{
  "aggregation": {
    "window.size.minutes": 0.5
  }
}
```

### Alterar paralelismo

Editar `config/application.json`:
```json
{
  "spark": {
    "shuffle.partitions": 20
  }
}
```

### Adicionar novo campo na agregação

1. Atualizar schema em `receivable_aggregator.py`:
```python
def get_kafka_schema():
    return StructType([
        # ... campos existentes
        StructField("novo_campo", StringType(), True)
    ])
```

2. Atualizar enriquecimento em `dynamodb_enricher.py`:
```python
def enrich_receivable(...):
    # ... código existente
    return {
        # ... campos existentes
        "novo_campo": item.get('novo_campo')
    }
```

## Exemplo 9: Produção

### Executar com mais recursos
```bash
spark-submit \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  --driver-memory 4g \
  --executor-memory 4g \
  --num-executors 2 \
  --executor-cores 2 \
  src/receivable_aggregator.py
```

### Usar checkpoint em HDFS
```json
{
  "spark": {
    "checkpoint.location": "hdfs://namenode:9000/spark-checkpoints"
  }
}
```

### Configurar retry e timeout
```python
# Em dynamodb_enricher.py
dynamodb = boto3.resource(
    'dynamodb',
    endpoint_url=endpoint,
    region_name=region,
    config=Config(
        retries={'max_attempts': 3},
        connect_timeout=5,
        read_timeout=10
    )
)
```

## Exemplo 10: Integração com Airflow

```python
# airflow_dag.py
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

with DAG(
    'receivable_aggregator',
    start_date=datetime(2024, 12, 24),
    schedule_interval='@daily',
    catchup=False
) as dag:
    
    spark_job = BashOperator(
        task_id='run_spark_job',
        bash_command='cd /path/to/sparkjob && python run.py',
        dag=dag
    )
    
    validate = BashOperator(
        task_id='validate_results',
        bash_command='cd /path/to/scripts && ./validate-data-consistency.ps1',
        dag=dag
    )
    
    spark_job >> validate
```

## Notas

- Todos os exemplos assumem que você está no diretório `apacheflink`
- Ajuste paths e configurações conforme seu ambiente
- Para Windows PowerShell, substitua `./script.sh` por `.\script.ps1`
- Logs são escritos no console por padrão
