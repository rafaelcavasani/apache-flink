# Implementação Completa - Generic Event Aggregator

## pom.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.aggregator</groupId>
    <artifactId>flink-generic-aggregator</artifactId>
    <version>1.0.0</version>

    <properties>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <flink.version>1.18.0</flink.version>
        <scala.binary.version>2.12</scala.binary.version>
    </properties>

    <dependencies>
        <!-- Flink Core -->
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-streaming-java</artifactId>
            <version>${flink.version}</version>
            <scope>provided</scope>
        </dependency>

        <!-- Kafka Connector -->
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-connector-kafka</artifactId>
            <version>3.0.1-1.18</version>
        </dependency>

        <!-- Elasticsearch 7 Connector -->
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-connector-elasticsearch7</artifactId>
            <version>3.0.1-1.18</version>
        </dependency>

        <!-- AWS SDK for DynamoDB -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>dynamodb</artifactId>
            <version>2.20.0</version>
        </dependency>

        <!-- JSON Processing -->
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <version>2.15.2</version>
        </dependency>

        <!-- JSONPath -->
        <dependency>
            <groupId>com.jayway.jsonpath</groupId>
            <artifactId>json-path</artifactId>
            <version>2.8.0</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.4.1</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <artifactSet>
                                <excludes>
                                    <exclude>org.apache.flink:flink-shaded-force-shading</exclude>
                                    <exclude>com.google.code.findbugs:jsr305</exclude>
                                </excludes>
                            </artifactSet>
                            <filters>
                                <filter>
                                    <artifact>*:*</artifact>
                                    <excludes>
                                        <exclude>META-INF/*.SF</exclude>
                                        <exclude>META-INF/*.DSA</exclude>
                                        <exclude>META-INF/*.RSA</exclude>
                                    </excludes>
                                </filter>
                            </filters>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>com.aggregator.GenericEventAggregator</mainClass>
                                </transformer>
                            </transformers>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
```

## src/main/java/com/aggregator/GenericEventAggregator.java

```java
package com.aggregator;

import com.aggregator.functions.*;
import com.aggregator.models.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

import java.io.InputStream;
import java.util.Map;

public class GenericEventAggregator {
    
    public static void main(String[] args) throws Exception {
        // Carregar configuração
        ObjectMapper mapper = new ObjectMapper();
        InputStream configStream = GenericEventAggregator.class
            .getClassLoader()
            .getResourceAsStream("application.json");
        Map<String, Object> config = mapper.readValue(configStream, Map.class);
        
        // Setup Flink Environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        Map<String, Object> flinkConfig = (Map<String, Object>) config.get("flink");
        env.setParallelism((Integer) flinkConfig.get("parallelism"));
        env.enableCheckpointing((Integer) flinkConfig.get("checkpoint.interval.ms"));
        
        // Kafka Source
        Map<String, Object> kafkaConfig = (Map<String, Object>) config.get("kafka");
        KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
            .setBootstrapServers((String) kafkaConfig.get("bootstrap.servers"))
            .setTopics((String) kafkaConfig.get("input.topic"))
            .setGroupId((String) kafkaConfig.get("group.id"))
            .setStartingOffsets(OffsetsInitializer.earliest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();
        
        // Stream Pipeline
        Map<String, Object> aggConfig = (Map<String, Object>) config.get("aggregation");
        String idJsonPath = (String) aggConfig.get("id.jsonpath");
        int windowSizeMinutes = (Integer) aggConfig.get("window.size.minutes");
        
        DataStream<String> kafkaStream = env.fromSource(
            kafkaSource,
            WatermarkStrategy.noWatermarks(),
            "Kafka Source"
        );
        
        // Extract ID via JSONPath
        DataStream<EventWithId> eventsWithId = kafkaStream
            .map(new JsonPathExtractor(idJsonPath))
            .name("Extract Aggregation ID");
        
        // Persist individual events to DynamoDB
        Map<String, Object> dynamoConfig = (Map<String, Object>) config.get("dynamodb");
        eventsWithId.addSink(new DynamoDBEventWriter(dynamoConfig))
            .name("Persist Events to DynamoDB");
        
        // Aggregate by ID + Time Window
        DataStream<AggregationResult> aggregated = eventsWithId
            .keyBy(event -> event.getAggregationId())
            .window(TumblingEventTimeWindows.of(Time.minutes(windowSizeMinutes)))
            .process(new EventAggregator())
            .name("Aggregate Events");
        
        // Enrich with DynamoDB Historical Data
        DataStream<EnrichedAggregation> enriched = aggregated
            .map(new DynamoDBEnricher(dynamoConfig))
            .name("Enrich with DynamoDB");
        
        // Sink to Elasticsearch
        Map<String, Object> esConfig = (Map<String, Object>) config.get("elasticsearch");
        enriched.addSink(new ElasticsearchSink(esConfig))
            .name("Elasticsearch Sink");
        
        // Execute
        env.execute("Generic Event Aggregator");
    }
}
```

## src/main/java/com/aggregator/functions/JsonPathExtractor.java

```java
package com.aggregator.functions;

import com.aggregator.models.EventWithId;
import com.jayway.jsonpath.JsonPath;
import org.apache.flink.api.common.functions.MapFunction;

public class JsonPathExtractor implements MapFunction<String, EventWithId> {
    
    private final String idJsonPath;
    
    public JsonPathExtractor(String idJsonPath) {
        this.idJsonPath = idJsonPath;
    }
    
    @Override
    public EventWithId map(String jsonEvent) throws Exception {
        String aggregationId = JsonPath.read(jsonEvent, idJsonPath);
        return new EventWithId(aggregationId, jsonEvent);
    }
}
```

## src/main/java/com/aggregator/functions/EventAggregator.java

```java
package com.aggregator.functions;

import com.aggregator.models.AggregationResult;
import com.aggregator.models.EventWithId;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;

import java.util.ArrayList;
import java.util.List;

public class EventAggregator extends ProcessWindowFunction<EventWithId, AggregationResult, String, TimeWindow> {
    
    @Override
    public void process(
        String aggregationId,
        Context context,
        Iterable<EventWithId> events,
        Collector<AggregationResult> out
    ) throws Exception {
        List<String> eventList = new ArrayList<>();
        int count = 0;
        
        for (EventWithId event : events) {
            eventList.add(event.getJsonEvent());
            count++;
        }
        
        AggregationResult result = new AggregationResult();
        result.setAggregationId(aggregationId);
        result.setEventCount(count);
        result.setEvents(eventList);
        result.setWindowStart(context.window().getStart());
        result.setWindowEnd(context.window().getEnd());
        result.setProcessingTime(System.currentTimeMillis());
        
        out.collect(result);
    }
}
```

## src/main/java/com/aggregator/functions/DynamoDBEnricher.java

```java
package com.aggregator.functions;

import com.aggregator.models.AggregationResult;
import com.aggregator.models.EnrichedAggregation;
import com.jayway.jsonpath.JsonPath;
import org.apache.flink.api.common.functions.RichMapFunction;
import org.apache.flink.configuration.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.net.URI;
import java.util.*;

public class DynamoDBEnricher extends RichMapFunction<AggregationResult, EnrichedAggregation> {
    
    private final Map<String, Object> config;
    private transient DynamoDbClient dynamoClient;
    
    public DynamoDBEnricher(Map<String, Object> config) {
        this.config = config;
    }
    
    @Override
    public void open(Configuration parameters) throws Exception {
        String endpoint = (String) config.get("endpoint");
        String region = (String) config.get("region");
        
        dynamoClient = DynamoDbClient.builder()
            .endpointOverride(URI.create(endpoint))
            .region(Region.of(region))
            .credentialsProvider(DefaultCredentialsProvider.create())
            .build();
    }
    
    @Override
    public EnrichedAggregation map(AggregationResult aggregation) throws Exception {
        String tableName = (String) config.get("table.name");
        String partitionKey = (String) config.get("partition.key");
        
        List<Map<String, Object>> historicalEvents = new ArrayList<>();
        
        // Collect all unique aggregation IDs from events (in this case, just one)
        Set<String> aggregationIds = new HashSet<>();
        aggregationIds.add(aggregation.getAggregationId());
        
        // Build BatchGetItem request (up to 100 items per request)
        if (!aggregationIds.isEmpty()) {
            List<Map<String, AttributeValue>> keysToGet = new ArrayList<>();
            
            // For each aggregation ID, we want to get all events (Query is still needed for sort key)
            // But we can use Query once per aggregation ID instead of once per event
            for (String aggId : aggregationIds) {
                QueryRequest queryRequest = QueryRequest.builder()
                    .tableName(tableName)
                    .keyConditionExpression(partitionKey + " = :pk")
                    .expressionAttributeValues(Map.of(
                        ":pk", AttributeValue.builder().s(aggId).build()
                    ))
                    .build();
                
                QueryResponse response = dynamoClient.query(queryRequest);
                
                for (Map<String, AttributeValue> item : response.items()) {
                    Map<String, Object> eventMap = new HashMap<>();
                    item.forEach((key, value) -> {
                        if (value.s() != null) {
                            eventMap.put(key, value.s());
                        } else if (value.n() != null) {
                            eventMap.put(key, value.n());
                        } else if (value.bool() != null) {
                            eventMap.put(key, value.bool());
                        }
                    });
                    historicalEvents.add(eventMap);
                }
            }
        }
        
        EnrichedAggregation enriched = new EnrichedAggregation();
        enriched.setAggregationId(aggregation.getAggregationId());
        enriched.setEventCount(aggregation.getEventCount());
        enriched.setCurrentEvents(aggregation.getEvents());
        enriched.setHistoricalEvents(historicalEvents);
        enriched.setTotalEventCount(aggregation.getEventCount() + historicalEvents.size());
        enriched.setWindowStart(aggregation.getWindowStart());
        enriched.setWindowEnd(aggregation.getWindowEnd());
        enriched.setProcessingTime(aggregation.getProcessingTime());
        
        return enriched;
    }
    
    @Override
    public void close() throws Exception {
        if (dynamoClient != null) {
            dynamoClient.close();
        }
    }
}
```

## src/main/java/com/aggregator/functions/DynamoDBEventWriter.java

```java
package com.aggregator.functions;

import com.aggregator.models.EventWithId;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.BatchWriteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.BatchWriteItemResponse;
import software.amazon.awssdk.services.dynamodb.model.PutRequest;
import software.amazon.awssdk.services.dynamodb.model.WriteRequest;

import java.net.URI;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class DynamoDBEventWriter extends RichSinkFunction<EventWithId> {
    private final Map<String, Object> config;
    private final int batchSize;
    private transient DynamoDbClient dynamoClient;
    private transient ObjectMapper objectMapper;
    private transient List<Map<String, AttributeValue>> buffer;
    private transient String tableName;
    private transient String partitionKey;
    private transient String sortKey;
    private transient String sortKeyJsonPath;
    
    public DynamoDBEventWriter(Map<String, Object> config) {
        this.config = config;
        // DynamoDB BatchWriteItem suporta até 25 itens por request
        this.batchSize = config.containsKey("batch.size") 
            ? (Integer) config.get("batch.size") 
            : 25;
    }
    
    @Override
    public void open(Configuration parameters) throws Exception {
        super.open(parameters);
        
        String endpoint = (String) config.get("endpoint");
        String region = (String) config.get("region");
        
        this.dynamoClient = DynamoDbClient.builder()
            .endpointOverride(URI.create(endpoint))
            .region(Region.of(region))
            .credentialsProvider(DefaultCredentialsProvider.create())
            .build();
            
        this.objectMapper = new ObjectMapper();
        this.buffer = new ArrayList<>();
        this.tableName = (String) config.get("table.name");
        this.partitionKey = (String) config.get("partition.key");
        this.sortKey = (String) config.get("sort.key");
        this.sortKeyJsonPath = (String) config.get("sort.key.jsonpath");
    }
    
    @Override
    public void invoke(EventWithId eventWithId, Context context) throws Exception {
        // Parse JSON event
        Map<String, Object> eventMap = objectMapper.readValue(
            eventWithId.getOriginalEvent(), 
            Map.class
        );
        
        // Extract sort key value from event
        String sortKeyValue = JsonPath.read(eventWithId.getOriginalEvent(), sortKeyJsonPath);
        
        // Build DynamoDB item
        Map<String, AttributeValue> item = new HashMap<>();
        
        // Add partition key (id_recebivel)
        item.put(partitionKey, AttributeValue.builder()
            .s(eventWithId.getAggregationId())
            .build());
        
        // Add sort key (tipo_evento)
        item.put(sortKey, AttributeValue.builder()
            .s(sortKeyValue)
            .build());
        
        // Add all other event attributes
        for (Map.Entry<String, Object> entry : eventMap.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();
            
            // Skip if already added as key
            if (key.equals(partitionKey) || key.equals(sortKey)) {
                continue;
            }
            
            // Convert value to AttributeValue
            AttributeValue attrValue;
            if (value instanceof String) {
                attrValue = AttributeValue.builder().s((String) value).build();
            } else if (value instanceof Number) {
                attrValue = AttributeValue.builder().n(value.toString()).build();
            } else if (value instanceof Boolean) {
                attrValue = AttributeValue.builder().bool((Boolean) value).build();
            } else {
                // Convert complex objects to JSON string
                attrValue = AttributeValue.builder().s(objectMapper.writeValueAsString(value)).build();
            }
            
            item.put(key, attrValue);
        }
        
        // Add to buffer
        buffer.add(item);
        
        // Flush if buffer is full
        if (buffer.size() >= batchSize) {
            flushBuffer();
        }
    }
    
    private void flushBuffer() throws Exception {
        if (buffer.isEmpty()) {
            return;
        }
        
        // Build batch write request
        List<WriteRequest> writeRequests = new ArrayList<>();
        for (Map<String, AttributeValue> item : buffer) {
            writeRequests.add(WriteRequest.builder()
                .putRequest(PutRequest.builder().item(item).build())
                .build());
        }
        
        Map<String, List<WriteRequest>> requestItems = new HashMap<>();
        requestItems.put(tableName, writeRequests);
        
        BatchWriteItemRequest batchRequest = BatchWriteItemRequest.builder()
            .requestItems(requestItems)
            .build();
        
        // Execute batch write
        BatchWriteItemResponse response = dynamoClient.batchWriteItem(batchRequest);
        
        // Handle unprocessed items (retry logic could be added here)
        if (response.hasUnprocessedItems() && !response.unprocessedItems().isEmpty()) {
            System.err.println("Warning: " + response.unprocessedItems().size() + " unprocessed items");
            // In production, implement retry logic for unprocessed items
        }
        
        // Clear buffer
        buffer.clear();
    }
    
    @Override
    public void close() throws Exception {
        // Flush remaining items before closing
        flushBuffer();
        
        if (dynamoClient != null) {
            dynamoClient.close();
        }
    }
}
```

## src/main/java/com/aggregator/functions/ElasticsearchSink.java

```java
package com.aggregator.functions;

import com.aggregator.models.EnrichedAggregation;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.streaming.connectors.elasticsearch.ElasticsearchSinkFunction;
import org.apache.flink.streaming.connectors.elasticsearch.RequestIndexer;
import org.apache.flink.streaming.connectors.elasticsearch7.ElasticsearchSink;
import org.apache.http.HttpHost;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.client.Requests;
import org.elasticsearch.common.xcontent.XContentType;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class ElasticsearchSink extends ElasticsearchSink<EnrichedAggregation> {
    
    public ElasticsearchSink(Map<String, Object> config) {
        super(buildConfig(config), buildTransportAddresses(config), buildSinkFunction(config));
    }
    
    private static org.apache.flink.connector.elasticsearch.sink.ElasticsearchSinkBuilderBase.BulkFlushConfig buildConfig(Map<String, Object> config) {
        return new org.apache.flink.connector.elasticsearch.sink.ElasticsearchSinkBuilderBase.BulkFlushConfig.Builder()
            .setBulkFlushMaxActions((Integer) config.get("bulk.flush.max.actions"))
            .setBulkFlushInterval((Integer) config.get("bulk.flush.interval.ms"))
            .build();
    }
    
    private static List<HttpHost> buildTransportAddresses(Map<String, Object> config) {
        List<String> hosts = (List<String>) config.get("hosts");
        List<HttpHost> httpHosts = new ArrayList<>();
        
        for (String host : hosts) {
            httpHosts.add(HttpHost.create(host));
        }
        
        return httpHosts;
    }
    
    private static ElasticsearchSinkFunction<EnrichedAggregation> buildSinkFunction(Map<String, Object> config) {
        String indexName = (String) config.get("index.name");
        ObjectMapper mapper = new ObjectMapper();
        
        return new ElasticsearchSinkFunction<EnrichedAggregation>() {
            @Override
            public void process(EnrichedAggregation element, RuntimeContext ctx, RequestIndexer indexer) {
                try {
                    String json = mapper.writeValueAsString(element);
                    
                    IndexRequest request = Requests.indexRequest()
                        .index(indexName)
                        .id(element.getAggregationId() + "_" + element.getWindowEnd())
                        .source(json, XContentType.JSON);
                    
                    indexer.add(request);
                } catch (Exception e) {
                    throw new RuntimeException("Failed to index document", e);
                }
            }
        };
    }
}
```

## src/main/java/com/aggregator/models/EventWithId.java

```java
package com.aggregator.models;

public class EventWithId {
    private String aggregationId;
    private String jsonEvent;
    
    public EventWithId() {}
    
    public EventWithId(String aggregationId, String jsonEvent) {
        this.aggregationId = aggregationId;
        this.jsonEvent = jsonEvent;
    }
    
    public String getAggregationId() { return aggregationId; }
    public void setAggregationId(String aggregationId) { this.aggregationId = aggregationId; }
    
    public String getJsonEvent() { return jsonEvent; }
    public void setJsonEvent(String jsonEvent) { this.jsonEvent = jsonEvent; }
}
```

## src/main/java/com/aggregator/models/AggregationResult.java

```java
package com.aggregator.models;

import java.util.List;

public class AggregationResult {
    private String aggregationId;
    private int eventCount;
    private List<String> events;
    private long windowStart;
    private long windowEnd;
    private long processingTime;
    
    // Getters and Setters
    public String getAggregationId() { return aggregationId; }
    public void setAggregationId(String aggregationId) { this.aggregationId = aggregationId; }
    
    public int getEventCount() { return eventCount; }
    public void setEventCount(int eventCount) { this.eventCount = eventCount; }
    
    public List<String> getEvents() { return events; }
    public void setEvents(List<String> events) { this.events = events; }
    
    public long getWindowStart() { return windowStart; }
    public void setWindowStart(long windowStart) { this.windowStart = windowStart; }
    
    public long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(long windowEnd) { this.windowEnd = windowEnd; }
    
    public long getProcessingTime() { return processingTime; }
    public void setProcessingTime(long processingTime) { this.processingTime = processingTime; }
}
```

## src/main/java/com/aggregator/models/EnrichedAggregation.java

```java
package com.aggregator.models;

import java.util.List;
import java.util.Map;

public class EnrichedAggregation {
    private String aggregationId;
    private int eventCount;
    private List<String> currentEvents;
    private List<Map<String, Object>> historicalEvents;
    private int totalEventCount;
    private long windowStart;
    private long windowEnd;
    private long processingTime;
    
    // Getters and Setters
    public String getAggregationId() { return aggregationId; }
    public void setAggregationId(String aggregationId) { this.aggregationId = aggregationId; }
    
    public int getEventCount() { return eventCount; }
    public void setEventCount(int eventCount) { this.eventCount = eventCount; }
    
    public List<String> getCurrentEvents() { return currentEvents; }
    public void setCurrentEvents(List<String> currentEvents) { this.currentEvents = currentEvents; }
    
    public List<Map<String, Object>> getHistoricalEvents() { return historicalEvents; }
    public void setHistoricalEvents(List<Map<String, Object>> historicalEvents) { 
        this.historicalEvents = historicalEvents; 
    }
    
    public int getTotalEventCount() { return totalEventCount; }
    public void setTotalEventCount(int totalEventCount) { this.totalEventCount = totalEventCount; }
    
    public long getWindowStart() { return windowStart; }
    public void setWindowStart(long windowStart) { this.windowStart = windowStart; }
    
    public long getWindowEnd() { return windowEnd; }
    public void setWindowEnd(long windowEnd) { this.windowEnd = windowEnd; }
    
    public long getProcessingTime() { return processingTime; }
    public void setProcessingTime(long processingTime) { this.processingTime = processingTime; }
}
```

## src/main/resources/application.json

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
    "sort.key": "tipo_evento",
    "sort.key.jsonpath": "$.tipo_evento"
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

## Build & Deploy

```bash
# 1. Compilar
mvn clean package

# 2. Copiar JAR para diretório jobs
cp target/flink-generic-aggregator-1.0.0.jar ../

# 3. Submeter job
docker exec flink-jobmanager flink run -d \
  -c com.aggregator.GenericEventAggregator \
  /opt/flink/usrlib/flink-generic-aggregator-1.0.0.jar
```

## Estrutura Final

```
flink-generic-aggregator/
├── pom.xml
├── src/
│   └── main/
│       ├── java/
│       │   └── com/
│       │       └── aggregator/
│       │           ├── GenericEventAggregator.java
│       │           ├── functions/
│       │           │   ├── JsonPathExtractor.java
│       │           │   ├── EventAggregator.java
│       │           │   ├── DynamoDBEventWriter.java
│       │           │   ├── DynamoDBEnricher.java
│       │           │   └── ElasticsearchSink.java
│       │           └── models/
│       │               ├── EventWithId.java
│       │               ├── AggregationResult.java
│       │               └── EnrichedAggregation.java
│       └── resources/
│           └── application.json
└── target/
    └── flink-generic-aggregator-1.0.0.jar
```
