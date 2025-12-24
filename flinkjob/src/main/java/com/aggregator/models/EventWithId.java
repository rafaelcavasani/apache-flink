package com.aggregator.models;

import java.util.Map;

public class EventWithId {
    private String aggregationId;
    private String jsonEvent;
    private Map<String, Object> originalEvent;
    
    public EventWithId() {}
    
    public EventWithId(String aggregationId, String jsonEvent) {
        this.aggregationId = aggregationId;
        this.jsonEvent = jsonEvent;
    }
    
    public EventWithId(String aggregationId, String jsonEvent, Map<String, Object> originalEvent) {
        this.aggregationId = aggregationId;
        this.jsonEvent = jsonEvent;
        this.originalEvent = originalEvent;
    }
    
    public String getAggregationId() { return aggregationId; }
    public void setAggregationId(String aggregationId) { this.aggregationId = aggregationId; }
    
    public String getJsonEvent() { return jsonEvent; }
    public void setJsonEvent(String jsonEvent) { this.jsonEvent = jsonEvent; }
    
    public Map<String, Object> getOriginalEvent() { return originalEvent; }
    public void setOriginalEvent(Map<String, Object> originalEvent) { this.originalEvent = originalEvent; }
}