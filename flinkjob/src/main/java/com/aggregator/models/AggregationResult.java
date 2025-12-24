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