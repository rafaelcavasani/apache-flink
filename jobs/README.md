# Generic Event Aggregator - Apache Flink Job

## Visão Geral

Job Flink **genérico e schema-agnostic** que:
1. ✅ Consome eventos do Kafka (qualquer schema JSON)
2. ✅ Agrega por ID customizável via JSONPath
3. ✅ Busca eventos históricos no DynamoDB (Event Store) usando PK e SK configuráveis
4. ✅ Salva agregações finais no Elasticsearch

## Arquitetura

```
Kafka → Flink (Aggregation) → DynamoDB (Enrich) → Elasticsearch
```

## Configuração Completa

### application.json

```json
{
  "kafka": {
    "bootstrap.servers": "kafka:29092",
    "group.id": "flink-aggregator",
    "input.topic": "recebiveis-eventos",
    "auto.offset.reset": "earliest"
  },
  "aggregation": {
    "id.jsonpath": "$.id_recebivel",
    "window.size.minutes": 5,
    "allowed.lateness.minutes": 1
  },
  "dynamodb": {
    "endpoint": "http://dynamodb:8000",
    "region": "us-east-1",
    "table.name": "Recebiveis",
    "partition.key": "id_recebivel",
    "sort.key": "timestamp",
    "sort.key.jsonpath": "$.timestamp"
  },
  "elasticsearch": {
    "hosts": ["http://elasticsearch:9200"],
    "index.name": "agregacoes-finais",
    "bulk.flush.max.actions": 1000,
    "bulk.flush.interval.ms": 5000
  },
  "flink": {
    "checkpoint.interval.ms": 60000,
    "parallelism": 2
  }
}
```

## Projeto Maven Completo


