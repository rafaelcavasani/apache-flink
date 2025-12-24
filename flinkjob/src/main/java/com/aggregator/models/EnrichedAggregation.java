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