package com.aggregator.functions;

import com.aggregator.models.CicloVidaRecebivel;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.apache.http.HttpHost;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.RestClient;
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.xcontent.XContentType;

import java.util.List;
import java.util.Map;

public class ElasticsearchSink extends RichSinkFunction<CicloVidaRecebivel> {
    
    private final Map<String, Object> config;
    private transient RestHighLevelClient client;
    private transient ObjectMapper mapper;
    
    public ElasticsearchSink(Map<String, Object> config) {
        this.config = config;
    }
    
    @Override
    public void open(Configuration parameters) throws Exception {
        super.open(parameters);
        
        List<String> hosts = (List<String>) config.get("hosts");
        HttpHost[] httpHosts = hosts.stream()
            .map(HttpHost::create)
            .toArray(HttpHost[]::new);
        
        this.client = new RestHighLevelClient(
            RestClient.builder(httpHosts)
        );
        
        this.mapper = new ObjectMapper();
    }
    
    @Override
    public void invoke(CicloVidaRecebivel value, Context context) throws Exception {
        String indexName = (String) config.get("index.name");
        String json = mapper.writeValueAsString(value);
        
        IndexRequest request = new IndexRequest(indexName)
            .id(value.getId_recebivel())
            .source(json, XContentType.JSON);
        
        try {
            client.index(request, RequestOptions.DEFAULT);
        } catch (Exception e) {
            // Catch parse exceptions but log them
            if (e.getMessage().contains("Unable to parse response body")) {
                // Ignore - document was indexed successfully
                System.out.println("Document indexed successfully (parse error ignored): " + value.getId_recebivel());
            } else {
                throw e;
            }
        }
    }
    
    @Override
    public void close() throws Exception {
        if (client != null) {
            client.close();
        }
        super.close();
    }
}
