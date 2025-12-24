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
