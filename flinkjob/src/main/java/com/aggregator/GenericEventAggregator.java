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
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

import java.io.InputStream;
import java.util.List;
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
        // Checkpointing disabled for local testing
        // env.enableCheckpointing((Integer) flinkConfig.get("checkpoint.interval.ms"));
        
        // Kafka Source
        Map<String, Object> kafkaConfig = (Map<String, Object>) config.get("kafka");
        List<String> topics = (List<String>) kafkaConfig.get("input.topics");
        KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
            .setBootstrapServers((String) kafkaConfig.get("bootstrap.servers"))
            .setTopics(topics)
            .setGroupId((String) kafkaConfig.get("group.id"))
            .setStartingOffsets(OffsetsInitializer.earliest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();
        
        // Stream Pipeline
        Map<String, Object> aggConfig = (Map<String, Object>) config.get("aggregation");
        String idJsonPath = (String) aggConfig.get("id.jsonpath");
        double windowSizeMinutes = ((Number) aggConfig.get("window.size.minutes")).doubleValue();
        long windowSizeSeconds = (long) (windowSizeMinutes * 60);
        
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
            .window(TumblingProcessingTimeWindows.of(Time.seconds(windowSizeSeconds)))
            .process(new EventAggregator())
            .name("Aggregate Events");
        
        // Enrich with DynamoDB Historical Data
        DataStream<CicloVidaRecebivel> enriched = aggregated
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
