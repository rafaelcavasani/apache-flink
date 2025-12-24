# Spark Structured Streaming Job - Receivable Aggregator

Versão em PySpark do job de agregação de recebíveis, equivalente ao job Flink implementado em Java.

## Descrição

Este projeto implementa um pipeline de streaming que:

1. **Consome eventos** de múltiplos tópicos Kafka (agendados, cancelados, negociados)
2. **Agrega eventos** por `id_recebivel` em janelas de tempo configuráveis
3. **Persiste eventos individuais** no DynamoDB para histórico completo
4. **Enriquece agregações** consultando o histórico completo no DynamoDB
5. **Calcula métricas** como valor disponível, totais cancelados/negociados
6. **Indexa no Elasticsearch** para consultas e análises

## Arquitetura

```
Kafka Topics → Spark Streaming → DynamoDB (Write Events)
                     ↓
              Time Window Aggregation
                     ↓
              DynamoDB Enrichment (Read Historical Data)
                     ↓
              Calculate Metrics
                     ↓
              Elasticsearch (Index Aggregated Data)
```

## Estrutura do Projeto

```
sparkjob/
├── src/
│   ├── receivable_aggregator.py     # Job principal (equivalente a GenericEventAggregator.java)
│   ├── dynamodb_writer.py            # Escrita de eventos (equivalente a DynamoDBEventWriter.java)
│   ├── dynamodb_enricher.py          # Enriquecimento (equivalente a DynamoDBEnricher.java)
│   └── elasticsearch_writer.py       # Escrita no ES (equivalente a ElasticsearchSink.java)
├── config/
│   └── application.json              # Configurações
├── requirements.txt                  # Dependências Python
└── README.md                         # Este arquivo
```

## Componentes

### 1. Receivable Aggregator (Main Job)
- **Arquivo**: `receivable_aggregator.py`
- **Função**: Orquestra todo o pipeline de streaming
- **Equivalente Flink**: `GenericEventAggregator.java`

**Funcionalidades**:
- Lê eventos do Kafka
- Agrega por `id_recebivel` em janelas de tempo
- Processa micro-batches com DynamoDB e Elasticsearch

### 2. DynamoDB Writer
- **Arquivo**: `dynamodb_writer.py`
- **Função**: Persiste eventos individuais no DynamoDB
- **Equivalente Flink**: `DynamoDBEventWriter.java`

**Funcionalidades**:
- Extrai eventos individuais do batch agregado
- Escreve cada evento no DynamoDB com batch writer
- Mantém histórico completo de todos os eventos

### 3. DynamoDB Enricher
- **Arquivo**: `dynamodb_enricher.py`
- **Função**: Enriquece agregações com dados históricos
- **Equivalente Flink**: `DynamoDBEnricher.java`

**Funcionalidades**:
- Consulta todos os eventos históricos por `id_recebivel`
- Extrai campos do evento base (agendado)
- Agrega cancelamentos e negociações
- Calcula `valor_disponivel = valor_original - total_cancelado - total_negociado`

### 4. Elasticsearch Writer
- **Arquivo**: `elasticsearch_writer.py`
- **Função**: Indexa dados enriquecidos no Elasticsearch
- **Equivalente Flink**: `ElasticsearchSink.java`

**Funcionalidades**:
- Converte dados para formato JSON
- Usa bulk API para performance
- Fallback para escrita individual em caso de erro

## Configuração

### application.json

```json
{
  "kafka": {
    "bootstrap.servers": "localhost:9092",
    "group.id": "spark-aggregator",
    "input.topics": ["recebiveis-agendados", "recebiveis-cancelados", "recebiveis-negociados"]
  },
  "aggregation": {
    "window.size.minutes": 0.25
  },
  "dynamodb": {
    "endpoint": "http://localhost:8000",
    "region": "us-east-1",
    "table.name": "Recebiveis"
  },
  "elasticsearch": {
    "hosts": ["http://localhost:9200"],
    "index.name": "ciclo_vida_recebiveis"
  },
  "spark": {
    "checkpoint.location": "/tmp/spark-checkpoints",
    "shuffle.partitions": 10
  }
}
```

## Instalação

### Pré-requisitos

- Python 3.8+
- Apache Spark 3.5.0
- Kafka running
- DynamoDB Local running
- Elasticsearch running

### Instalar Dependências

```bash
pip install -r requirements.txt
```

### Configurar Variáveis de Ambiente

```bash
# AWS credentials para DynamoDB Local
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=us-east-1

# Spark home (opcional)
export SPARK_HOME=/path/to/spark
```

## Execução

### Executar Localmente

```bash
cd sparkjob

# Executar com spark-submit
spark-submit \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.elasticsearch:elasticsearch-spark-30_2.12:8.11.0 \
  src/receivable_aggregator.py
```

### Executar com Python (modo standalone)

```bash
python src/receivable_aggregator.py
```

## Monitoramento

### Logs

O job gera logs estruturados com as seguintes informações:

```
2024-12-24 18:30:00 [INFO] receivable_aggregator - Starting Receivable Aggregator Spark Job
2024-12-24 18:30:01 [INFO] receivable_aggregator - Configuration loaded successfully
2024-12-24 18:30:02 [INFO] receivable_aggregator - Reading from Kafka topics: recebiveis-agendados,recebiveis-cancelados,recebiveis-negociados
2024-12-24 18:30:03 [INFO] receivable_aggregator - Configuring aggregation with window duration: 15 seconds
2024-12-24 18:30:05 [INFO] receivable_aggregator - Processing batch 0 with 100 records
2024-12-24 18:30:06 [INFO] dynamodb_writer - Writing 100 events to DynamoDB table: Recebiveis
2024-12-24 18:30:07 [INFO] dynamodb_enricher - [ENRICH] Starting enrichment for id_recebivel: abc-123
2024-12-24 18:30:08 [INFO] elasticsearch_writer - Writing 50 records to Elasticsearch
```

### Spark UI

Acesse a interface web do Spark para monitorar:
- **URL**: http://localhost:4040
- Visualize jobs, stages, tasks
- Monitore uso de memória e CPU
- Acompanhe progresso do streaming

## Validação

### Verificar Eventos no DynamoDB

```bash
aws dynamodb scan --table-name Recebiveis --endpoint-url http://localhost:8000 --region us-east-1
```

### Verificar Agregações no Elasticsearch

```bash
curl -X GET "localhost:9200/ciclo_vida_recebiveis/_search?pretty"
```

### Verificar um Recebível Específico

```bash
curl -X GET "localhost:9200/ciclo_vida_recebiveis/_doc/{id_recebivel}?pretty"
```

## Comparação com Flink

| Aspecto | Flink (Java) | Spark (Python) |
|---------|--------------|----------------|
| Linguagem | Java | Python |
| Framework | Apache Flink | Apache Spark Structured Streaming |
| Windowing | TumblingProcessingTimeWindows | window() function |
| State | RichMapFunction | UDF with external state (DynamoDB) |
| Checkpointing | Built-in | Checkpoint location |
| Parallelism | setParallelism() | shuffle.partitions |
| Sink | RichSinkFunction | foreachBatch() |

## Diferenças Principais

1. **Processamento de Estado**:
   - **Flink**: Estado gerenciado internamente pelo RichMapFunction
   - **Spark**: Estado externo no DynamoDB, consultado via UDF

2. **Janelas de Tempo**:
   - **Flink**: TumblingProcessingTimeWindows nativo
   - **Spark**: window() function com processing time

3. **Sink/Output**:
   - **Flink**: Custom RichSinkFunction para cada sink
   - **Spark**: foreachBatch() que chama funções Python

4. **Serialização**:
   - **Flink**: Classes Java serializáveis
   - **Spark**: Schemas PySpark + conversão para dicts

## Performance

### Throughput Esperado
- **Eventos/segundo**: ~50-100 (similar ao Flink)
- **Agregações/segundo**: ~25-50
- **Latência**: 15-30 segundos (janela + processamento)

### Otimizações
- Use `shuffle.partitions` adequado para seu volume de dados
- Configure `checkpoint.location` em storage distribuído para produção
- Ajuste `window.size.minutes` baseado em seus requisitos de latência
- Use batch writer do DynamoDB para melhor performance

## Troubleshooting

### Erro: "Unable to load AWS credentials"
```bash
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
```

### Erro: "Connection refused to Kafka"
Verifique se Kafka está rodando:
```bash
docker ps | grep kafka
```

### Erro: "Index not found" no Elasticsearch
Crie o índice manualmente:
```bash
curl -X PUT "localhost:9200/ciclo_vida_recebiveis"
```

## Desenvolvimento

### Adicionar Novos Campos

1. Atualizar schema em `get_kafka_schema()`
2. Atualizar `get_enriched_schema()`
3. Adicionar lógica de extração em `enrich_receivable()`
4. Atualizar DynamoDB writer se necessário

### Testes

```bash
# Executar producer de teste
cd ../producer
go run main.go -count 100

# Verificar processamento
tail -f /tmp/spark-checkpoints/offsets/0
```

## Licença

Este projeto é parte do sistema de agregação de recebíveis.

## Contato

Para dúvidas ou problemas, consulte a documentação do projeto principal.
