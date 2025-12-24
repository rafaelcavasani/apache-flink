package com.aggregator.functions;

import com.aggregator.models.EventWithId;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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
    private static final Logger LOG = LoggerFactory.getLogger(DynamoDBEventWriter.class);
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
        // Use batch size 1 for immediate writes to avoid race conditions
        this.batchSize = 1;
        LOG.info("[WRITER] DynamoDBEventWriter initialized with batch size: {}", this.batchSize);
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
        // Get event map
        Map<String, Object> eventMap = eventWithId.getOriginalEvent();
        
        // Extract sort key value from JSON event string
        String sortKeyValue = JsonPath.read(eventWithId.getJsonEvent(), sortKeyJsonPath);
        
        LOG.info("[WRITER] Writing event: id={}, sortKey={}", eventWithId.getAggregationId(), sortKeyValue);
        
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
        
        LOG.info("[WRITER] Flushing {} events to DynamoDB", buffer.size());
        
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
            LOG.error("[WRITER] Warning: {} unprocessed items", response.unprocessedItems().size());
        } else {
            LOG.info("[WRITER] Successfully wrote {} events to DynamoDB", buffer.size());
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