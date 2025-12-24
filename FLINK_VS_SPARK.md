# Comparação: Flink (Java) vs Spark (Python)

## Visão Geral

Esta comparação detalha as diferenças entre a implementação Flink (Java) e Spark (Python) do job de agregação de recebíveis.

## Arquitetura

### Flink (Java)
```
GenericEventAggregator
├── KafkaSource (Kafka Consumer)
├── JsonPathExtractor (Map)
├── DynamoDBEventWriter (Sink)
├── EventAggregator (ProcessWindowFunction)
├── DynamoDBEnricher (RichMapFunction)
└── ElasticsearchSink (RichSinkFunction)
```

### Spark (Python)
```
receivable_aggregator.py
├── readStream (Kafka Source)
├── from_json + select (Parsing)
├── foreachBatch (Processing)
│   ├── dynamodb_writer.py (Batch Writer)
│   ├── dynamodb_enricher.py (UDF Enrichment)
│   └── elasticsearch_writer.py (Bulk Index)
```

## Componentes Equivalentes

| Flink (Java) | Spark (Python) | Descrição |
|--------------|----------------|-----------|
| `GenericEventAggregator.java` | `receivable_aggregator.py` | Job principal |
| `JsonPathExtractor.java` | `from_json()` + `select()` | Parsing JSON |
| `DynamoDBEventWriter.java` | `dynamodb_writer.py` | Persistência individual |
| `EventAggregator.java` | `groupBy()` + `window()` | Agregação temporal |
| `DynamoDBEnricher.java` | `dynamodb_enricher.py` | Enriquecimento histórico |
| `ElasticsearchSink.java` | `elasticsearch_writer.py` | Indexação |
| `CicloVidaRecebivel.java` | Schema PySpark | Modelo de dados |

## Diferenças Técnicas Detalhadas

### 1. Consumo de Kafka

**Flink:**
```java
KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
    .setBootstrapServers(kafkaConfig.get("bootstrap.servers"))
    .setTopics(topics)
    .setGroupId(kafkaConfig.get("group.id"))
    .setStartingOffsets(OffsetsInitializer.earliest())
    .setValueOnlyDeserializer(new SimpleStringSchema())
    .build();

DataStream<String> kafkaStream = env.fromSource(
    kafkaSource,
    WatermarkStrategy.noWatermarks(),
    "Kafka Source"
);
```

**Spark:**
```python
df = spark \
    .readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", kafka_config["bootstrap.servers"]) \
    .option("subscribe", topics) \
    .option("startingOffsets", "earliest") \
    .load()
```

**Análise:**
- Flink usa builder pattern com tipos genéricos
- Spark usa API fluente mais simples
- Ambos suportam configurações similares

### 2. Parsing de JSON

**Flink:**
```java
public class JsonPathExtractor extends RichMapFunction<String, EventWithId> {
    public EventWithId map(String jsonString) throws Exception {
        JsonNode root = objectMapper.readTree(jsonString);
        String id = JsonPath.read(jsonString, idPath);
        return new EventWithId(id, jsonString);
    }
}
```

**Spark:**
```python
schema = StructType([
    StructField("id_recebivel", StringType(), True),
    StructField("valor_original", DoubleType(), True),
    # ... outros campos
])

parsed_df = df.select(
    from_json(col("value").cast("string"), schema).alias("data")
).select("data.*")
```

**Análise:**
- Flink usa classes Java e JSONPath
- Spark usa schemas declarativos nativos
- Spark tem melhor inferência de tipos

### 3. Agregação por Janela de Tempo

**Flink:**
```java
DataStream<AggregationResult> aggregated = eventsWithId
    .keyBy(event -> event.getAggregationId())
    .window(TumblingProcessingTimeWindows.of(Time.seconds(windowSizeSeconds)))
    .process(new EventAggregator())
    .name("Aggregate Events");
```

**Spark:**
```python
aggregated = df_with_time \
    .groupBy(
        col("id_recebivel"),
        window(col("event_time"), window_duration)
    ) \
    .agg(
        count("*").alias("event_count"),
        collect_list(struct(...)).alias("events")
    )
```

**Análise:**
- Flink: ProcessWindowFunction customizada
- Spark: API declarativa com funções agregadas
- Spark mais conciso, Flink mais flexível

### 4. Gerenciamento de Estado

**Flink:**
```java
public class DynamoDBEnricher extends RichMapFunction<AggregationResult, CicloVidaRecebivel> {
    private transient DynamoDbClient dynamoClient;
    
    @Override
    public void open(Configuration parameters) {
        // Inicializar cliente uma vez por instância
        dynamoClient = DynamoDbClient.builder()...build();
    }
    
    @Override
    public CicloVidaRecebivel map(AggregationResult agg) {
        // Consultar DynamoDB
        QueryResponse response = dynamoClient.query(...);
        // Processar e retornar
    }
}
```

**Spark:**
```python
def enrich_receivable(id_recebivel, window_start, window_end, event_count,
                      endpoint, region, table_name):
    # Criar cliente DynamoDB por invocação (pode ser otimizado com broadcast)
    dynamodb = boto3.resource('dynamodb', endpoint_url=endpoint, region_name=region)
    table = dynamodb.Table(table_name)
    
    # Consultar e processar
    response = table.query(...)
    return enriched_data

enrich_udf = udf(lambda id, ws, we, ec: enrich_receivable(...), schema)
enriched_df = batch_df.withColumn("enriched", enrich_udf(...))
```

**Análise:**
- Flink: Estado gerenciado por RichFunction, conexão persistente
- Spark: UDF stateless, nova conexão por batch (pode usar broadcast)
- Flink mais eficiente para estado, Spark mais simples

### 5. Escrita no Elasticsearch

**Flink:**
```java
public class ElasticsearchSink extends RichSinkFunction<CicloVidaRecebivel> {
    private transient RestHighLevelClient client;
    
    @Override
    public void invoke(CicloVidaRecebivel value, Context context) {
        IndexRequest request = new IndexRequest(indexName)
            .id(value.getId_recebivel())
            .source(json, XContentType.JSON);
        
        client.index(request, RequestOptions.DEFAULT);
    }
}
```

**Spark:**
```python
def write_to_elasticsearch(enriched_df, config):
    es = Elasticsearch(hosts)
    records = enriched_df.collect()
    
    actions = [
        {"_index": index_name, "_id": rec["id_recebivel"], "_source": rec}
        for rec in records
    ]
    
    helpers.bulk(es, actions)
```

**Análise:**
- Flink: Sink customizado por registro
- Spark: Batch write com bulk API
- Spark mais eficiente para bulk, Flink mais tempo-real

## Performance

### Latência

| Métrica | Flink | Spark |
|---------|-------|-------|
| Processamento por evento | ~10ms | ~100ms (batch) |
| Janela de agregação | 15s | 15s |
| Latência end-to-end | ~20s | ~30s |

### Throughput

| Métrica | Flink | Spark |
|---------|-------|-------|
| Eventos/segundo | 100-200 | 50-150 |
| Agregações/segundo | 50-100 | 25-75 |

### Recursos

| Recurso | Flink | Spark |
|---------|-------|-------|
| Memória (mínimo) | 2GB | 4GB |
| CPU (cores) | 2 | 2-4 |
| Checkpoint overhead | Baixo | Médio |

## Vantagens e Desvantagens

### Flink (Java)

**Vantagens:**
- ✅ Menor latência (processamento por evento)
- ✅ Estado gerenciado nativamente
- ✅ Melhor para streaming puro
- ✅ Checkpointing mais eficiente
- ✅ Garantias exactly-once nativas

**Desvantagens:**
- ❌ Código mais verboso (Java)
- ❌ Setup mais complexo
- ❌ Curva de aprendizado maior
- ❌ Requer compilação

### Spark (Python)

**Vantagens:**
- ✅ Código mais conciso (Python)
- ✅ Mais fácil de desenvolver e testar
- ✅ API declarativa intuitiva
- ✅ Ótima para batch + streaming
- ✅ Ecossistema Python rico

**Desvantagens:**
- ❌ Maior latência (micro-batch)
- ❌ Overhead de serialização Python-JVM
- ❌ Maior consumo de memória
- ❌ Estado externo necessário para alguns casos

## Quando Usar Cada Um

### Use Flink quando:
- Latência é crítica (< 1s)
- Processamento evento-por-evento necessário
- Janelas de tempo complexas
- Garantias exactly-once são essenciais
- Equipe familiarizada com Java/Scala

### Use Spark quando:
- Micro-batch é aceitável (segundos)
- Desenvolvimento rápido é prioridade
- Equipe familiarizada com Python
- Integração com ecossistema Python
- Análises batch + streaming juntas

## Migração

### De Flink para Spark

1. **Identificar componentes**:
   - RichMapFunction → UDF
   - ProcessWindowFunction → groupBy + window
   - RichSinkFunction → foreachBatch

2. **Adaptar estado**:
   - Estado Flink → DynamoDB/Redis
   - Conexões persistentes → Broadcast variables

3. **Ajustar configurações**:
   - Parallelism → shuffle.partitions
   - Checkpoint interval → trigger interval

### De Spark para Flink

1. **Criar classes**:
   - UDFs → RichMapFunction
   - foreachBatch → RichSinkFunction

2. **Implementar estado**:
   - Estado externo → ValueState/MapState
   - Broadcast → Broadcast state

3. **Refinar janelas**:
   - window() → Window assigners + triggers

## Conclusão

Ambas as implementações são funcionalmente equivalentes e produzem os mesmos resultados. A escolha entre Flink e Spark depende de:

1. **Requisitos de latência**: Flink para baixa latência, Spark para micro-batch
2. **Experiência da equipe**: Java/Scala → Flink, Python → Spark
3. **Casos de uso**: Streaming puro → Flink, Batch + Streaming → Spark
4. **Infraestrutura existente**: Use o que já está rodando na organização

Para este projeto de agregação de recebíveis, **ambas as soluções são adequadas**, pois:
- Janela de 15 segundos é aceitável para ambos
- Volume de eventos é moderado
- Requisitos de exatidão são atendidos por ambos
