package com.aggregator.functions;

import com.aggregator.models.EventWithId;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.jayway.jsonpath.JsonPath;
import org.apache.flink.api.common.functions.MapFunction;

import java.util.Map;

public class JsonPathExtractor implements MapFunction<String, EventWithId> {
    
    private final String idJsonPath;
    private transient ObjectMapper mapper;
    
    public JsonPathExtractor(String idJsonPath) {
        this.idJsonPath = idJsonPath;
    }
    
    @Override
    public EventWithId map(String jsonEvent) throws Exception {
        if (mapper == null) {
            mapper = new ObjectMapper();
        }
        
        String aggregationId = JsonPath.read(jsonEvent, idJsonPath);
        Map<String, Object> eventMap = mapper.readValue(jsonEvent, Map.class);
        
        return new EventWithId(aggregationId, jsonEvent, eventMap);
    }
}

