package com.aggregator.functions;

import com.aggregator.models.AggregationResult;
import com.aggregator.models.CicloVidaRecebivel;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.functions.RichMapFunction;
import org.apache.flink.configuration.Configuration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.net.URI;
import java.util.*;

public class DynamoDBEnricher extends RichMapFunction<AggregationResult, CicloVidaRecebivel> {
    
    private static final Logger LOG = LoggerFactory.getLogger(DynamoDBEnricher.class);
    private final Map<String, Object> config;
    private transient DynamoDbClient dynamoClient;
    private transient ObjectMapper objectMapper;
    
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
            
        objectMapper = new ObjectMapper();
    }
    
    @Override
    public CicloVidaRecebivel map(AggregationResult aggregation) throws Exception {
        String tableName = (String) config.get("table.name");
        String partitionKey = (String) config.get("partition.key");
        String aggId = aggregation.getAggregationId();
        
        LOG.info("[ENRICH] Starting enrichment for id_recebivel: {}", aggId);
        
        CicloVidaRecebivel ciclo = new CicloVidaRecebivel();
        ciclo.setId_recebivel(aggId);
        ciclo.setWindow_start(aggregation.getWindowStart());
        ciclo.setWindow_end(aggregation.getWindowEnd());
        ciclo.setQuantidade_eventos(aggregation.getEventCount());
        
        // Lists for cancelamentos and negociacoes
        List<CicloVidaRecebivel.Cancelamento> cancelamentos = new ArrayList<>();
        List<CicloVidaRecebivel.Negociacao> negociacoes = new ArrayList<>();
        
        // Fetch all events from DynamoDB for this id_recebivel
        QueryRequest queryRequest = QueryRequest.builder()
            .tableName(tableName)
            .keyConditionExpression(partitionKey + " = :pk")
            .expressionAttributeValues(Map.of(
                ":pk", AttributeValue.builder().s(aggId).build()
            ))
            .build();
        
        QueryResponse response = dynamoClient.query(queryRequest);
        LOG.info("[ENRICH] Retrieved {} events from DynamoDB for id_recebivel: {}", response.count(), aggId);
        
        // Variables for aggregation
        Double valorOriginal = null;
        String idPagamento = null;
        Integer codigoProduto = null;
        Integer codigoProdutoParceiro = null;
        Integer modalidade = null;
        String dataVencimento = null;
        String timestamp = null;
        double totalCancelado = 0.0;
        double totalNegociado = 0.0;
        
        // Process all events
        for (Map<String, AttributeValue> item : response.items()) {
            String tipoEvento = item.get("tipo_evento") != null ? item.get("tipo_evento").s() : "";
            LOG.debug("  [ENRICH] Processing event type: {} for id: {}", tipoEvento, aggId);
            
            // Extract common fields from first event (agendado)
            if ("agendado".equals(tipoEvento)) {
                if (valorOriginal == null && item.get("valor_original") != null && item.get("valor_original").n() != null) {
                    try {
                        valorOriginal = Double.parseDouble(item.get("valor_original").n());
                        LOG.info("  [ENRICH] Extracted valor_original: {} for id: {}", valorOriginal, aggId);
                    } catch (NumberFormatException e) {
                        LOG.error("  [ENRICH] Failed to parse valor_original for id: {}", aggId, e);
                    }
                }
                if (idPagamento == null && item.get("id_pagamento") != null) {
                    idPagamento = item.get("id_pagamento").s();
                }
                if (codigoProduto == null && item.get("codigo_produto") != null && item.get("codigo_produto").n() != null) {
                    try {
                        codigoProduto = Integer.parseInt(item.get("codigo_produto").n());
                    } catch (NumberFormatException e) {
                        // Ignore parse errors
                    }
                }
                if (codigoProdutoParceiro == null && item.get("codigo_produto_parceiro") != null && item.get("codigo_produto_parceiro").n() != null) {
                    try {
                        codigoProdutoParceiro = Integer.parseInt(item.get("codigo_produto_parceiro").n());
                    } catch (NumberFormatException e) {
                        // Ignore parse errors
                    }
                }
                if (modalidade == null && item.get("modalidade") != null && item.get("modalidade").n() != null) {
                    try {
                        modalidade = Integer.parseInt(item.get("modalidade").n());
                    } catch (NumberFormatException e) {
                        // Ignore parse errors
                    }
                }
                if (dataVencimento == null && item.get("data_vencimento") != null) {
                    dataVencimento = item.get("data_vencimento").s();
                }
                if (timestamp == null && item.get("timestamp") != null) {
                    timestamp = item.get("timestamp").s();
                }
            }
            
            // Process cancelamentos
            if ("cancelado".equals(tipoEvento)) {
                CicloVidaRecebivel.Cancelamento cancelamento = new CicloVidaRecebivel.Cancelamento();
                
                if (item.get("id_cancelamento") != null) {
                    cancelamento.setId_cancelamento(item.get("id_cancelamento").s());
                }
                if (item.get("data_cancelamento") != null) {
                    cancelamento.setData_cancelamento(item.get("data_cancelamento").s());
                }
                if (item.get("valor_cancelado") != null && item.get("valor_cancelado").n() != null) {
                    try {
                        double valor = Double.parseDouble(item.get("valor_cancelado").n());
                        cancelamento.setValor_cancelado(valor);
                        totalCancelado += valor;
                        LOG.info("  [ENRICH] Added cancelamento with value: {} for id: {}", valor, aggId);
                    } catch (NumberFormatException e) {
                        LOG.error("  [ENRICH] Failed to parse valor_cancelado for id: {}", aggId, e);
                    }
                }
                if (item.get("motivo") != null) {
                    cancelamento.setMotivo(item.get("motivo").s());
                }
                
                cancelamentos.add(cancelamento);
            }
            
            // Process negociacoes
            if ("negociado".equals(tipoEvento)) {
                CicloVidaRecebivel.Negociacao negociacao = new CicloVidaRecebivel.Negociacao();
                
                if (item.get("id_negociacao") != null) {
                    negociacao.setId_negociacao(item.get("id_negociacao").s());
                }
                if (item.get("data_negociacao") != null) {
                    negociacao.setData_negociacao(item.get("data_negociacao").s());
                }
                if (item.get("valor_negociado") != null && item.get("valor_negociado").n() != null) {
                    try {
                        double valor = Double.parseDouble(item.get("valor_negociado").n());
                        negociacao.setValor_negociado(valor);
                        totalNegociado += valor;
                        LOG.info("  [ENRICH] Added negociacao with value: {} for id: {}", valor, aggId);
                    } catch (NumberFormatException e) {
                        LOG.error("  [ENRICH] Failed to parse valor_negociado for id: {}", aggId, e);
                    }
                }
                
                negociacoes.add(negociacao);
            }
        }
        
        // Set all fields
        ciclo.setId_pagamento(idPagamento);
        ciclo.setCodigo_produto(codigoProduto);
        ciclo.setCodigo_produto_parceiro(codigoProdutoParceiro);
        ciclo.setModalidade(modalidade);
        ciclo.setValor_original(valorOriginal);
        ciclo.setData_vencimento(dataVencimento);
        ciclo.setTimestamp(timestamp);
        
        ciclo.setCancelamentos(cancelamentos);
        ciclo.setNegociacoes(negociacoes);
        
        ciclo.setQuantidade_cancelamentos(cancelamentos.size());
        ciclo.setQuantidade_negociacoes(negociacoes.size());
        
        ciclo.setValor_total_cancelado(totalCancelado);
        ciclo.setValor_total_negociado(totalNegociado);
        
        // Calculate valor_disponivel
        double valorDisponivel = (valorOriginal != null ? valorOriginal : 0.0) - totalCancelado - totalNegociado;
        ciclo.setValor_disponivel(valorDisponivel);
        
        LOG.info("[ENRICH] Completed enrichment for id: {} - valor_original: {}, cancelamentos: {}, negociacoes: {}, total_cancelado: {}, total_negociado: {}", 
                 aggId, valorOriginal, cancelamentos.size(), negociacoes.size(), totalCancelado, totalNegociado);
        
        return ciclo;
    }
    
    @Override
    public void close() throws Exception {
        if (dynamoClient != null) {
            dynamoClient.close();
        }
    }
}
