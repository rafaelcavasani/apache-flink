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

### 1. Estrutura do Projeto Maven

```xml
<dependencies>
    <!-- Flink -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-streaming-java</artifactId>
        <version>1.18.0</version>
    </dependency>
    
    <!-- Kafka Connector -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-connector-kafka</artifactId>
        <version>3.0.1-1.18</version>
    </dependency>
    
    <!-- Elasticsearch Connector -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-connector-elasticsearch7</artifactId>
        <version>3.0.1-1.18</version>
    </dependency>
    
    <!-- JSON -->
    <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.15.2</version>
    </dependency>
</dependencies>
```

### 2. Exemplo de Job (pseudocódigo)

```java
public class RecebiveisAggregationJob {
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Configurar checkpointing
        env.enableCheckpointing(60000); // 1 minuto
        
        // Source: Kafka
        KafkaSource<String> source = KafkaSource.<String>builder()
            .setBootstrapServers("kafka:29092")
            .setTopics("recebiveis-eventos")
            .setGroupId("flink-consumer")
            .setStartingOffsets(OffsetsInitializer.earliest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();
        
        DataStream<String> stream = env.fromSource(source, 
            WatermarkStrategy.noWatermarks(), "Kafka Source");
        
        // Transformação: Parse JSON e agregação
        DataStream<Agregacao> agregado = stream
            .map(json -> parseJson(json))
            .keyBy(evento -> evento.getCodigoCliente())
            .window(TumblingEventTimeWindows.of(Time.minutes(5)))
            .aggregate(new RecebiveisAggregator());
        
        // Sink: Elasticsearch
        ElasticsearchSink<Agregacao> esSink = new ElasticsearchSink.Builder<>(
            Collections.singletonList(new HttpHost("elasticsearch", 9200)),
            new ElasticsearchSinkFunction<Agregacao>() {
                @Override
                public void process(Agregacao element, RuntimeContext ctx, 
                                  RequestIndexer indexer) {
                    IndexRequest request = Requests.indexRequest()
                        .index("recebiveis-agregados")
                        .source(toMap(element));
                    indexer.add(request);
                }
            }
        ).build();
        
        agregado.addSink(esSink);
        
        env.execute("Recebíveis Aggregation Job");
    }
}
```

### 3. Build e Deploy

```bash
# Build do projeto
mvn clean package

# Copiar JAR para pasta jobs
cp target/recebiveis-job-1.0-SNAPSHOT.jar jobs/

# Submeter job via CLI
docker exec -it flink-jobmanager flink run /opt/flink/usrlib/recebiveis-job-1.0-SNAPSHOT.jar

# Ou submeter via Web UI: http://localhost:8081
```

## Submeter Job via Web UI

1. Acesse http://localhost:8081
2. Clique em "Submit New Job"
3. Selecione o JAR
4. Configure parâmetros (se necessário)
5. Clique em "Submit"
