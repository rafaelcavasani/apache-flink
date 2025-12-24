package com.aggregator.models;

import java.util.List;

public class CicloVidaRecebivel {
    private String id_recebivel;
    private String id_pagamento;
    private Integer codigo_produto;
    private Integer codigo_produto_parceiro;
    private Integer modalidade;
    private Double valor_original;
    private String data_vencimento;
    private List<Cancelamento> cancelamentos;
    private List<Negociacao> negociacoes;
    private Double valor_disponivel;
    private Double valor_total_cancelado;
    private Double valor_total_negociado;
    private Integer quantidade_eventos;
    private Integer quantidade_cancelamentos;
    private Integer quantidade_negociacoes;
    private String timestamp;
    private Long window_start;
    private Long window_end;
    
    // Getters and Setters
    public String getId_recebivel() { return id_recebivel; }
    public void setId_recebivel(String id_recebivel) { this.id_recebivel = id_recebivel; }
    
    public String getId_pagamento() { return id_pagamento; }
    public void setId_pagamento(String id_pagamento) { this.id_pagamento = id_pagamento; }
    
    public Integer getCodigo_produto() { return codigo_produto; }
    public void setCodigo_produto(Integer codigo_produto) { this.codigo_produto = codigo_produto; }
    
    public Integer getCodigo_produto_parceiro() { return codigo_produto_parceiro; }
    public void setCodigo_produto_parceiro(Integer codigo_produto_parceiro) { 
        this.codigo_produto_parceiro = codigo_produto_parceiro; 
    }
    
    public Integer getModalidade() { return modalidade; }
    public void setModalidade(Integer modalidade) { this.modalidade = modalidade; }
    
    public Double getValor_original() { return valor_original; }
    public void setValor_original(Double valor_original) { this.valor_original = valor_original; }
    
    public String getData_vencimento() { return data_vencimento; }
    public void setData_vencimento(String data_vencimento) { this.data_vencimento = data_vencimento; }
    
    public List<Cancelamento> getCancelamentos() { return cancelamentos; }
    public void setCancelamentos(List<Cancelamento> cancelamentos) { this.cancelamentos = cancelamentos; }
    
    public List<Negociacao> getNegociacoes() { return negociacoes; }
    public void setNegociacoes(List<Negociacao> negociacoes) { this.negociacoes = negociacoes; }
    
    public Double getValor_disponivel() { return valor_disponivel; }
    public void setValor_disponivel(Double valor_disponivel) { this.valor_disponivel = valor_disponivel; }
    
    public Double getValor_total_cancelado() { return valor_total_cancelado; }
    public void setValor_total_cancelado(Double valor_total_cancelado) { 
        this.valor_total_cancelado = valor_total_cancelado; 
    }
    
    public Double getValor_total_negociado() { return valor_total_negociado; }
    public void setValor_total_negociado(Double valor_total_negociado) { 
        this.valor_total_negociado = valor_total_negociado; 
    }
    
    public Integer getQuantidade_eventos() { return quantidade_eventos; }
    public void setQuantidade_eventos(Integer quantidade_eventos) { 
        this.quantidade_eventos = quantidade_eventos; 
    }
    
    public Integer getQuantidade_cancelamentos() { return quantidade_cancelamentos; }
    public void setQuantidade_cancelamentos(Integer quantidade_cancelamentos) { 
        this.quantidade_cancelamentos = quantidade_cancelamentos; 
    }
    
    public Integer getQuantidade_negociacoes() { return quantidade_negociacoes; }
    public void setQuantidade_negociacoes(Integer quantidade_negociacoes) { 
        this.quantidade_negociacoes = quantidade_negociacoes; 
    }
    
    public String getTimestamp() { return timestamp; }
    public void setTimestamp(String timestamp) { this.timestamp = timestamp; }
    
    public Long getWindow_start() { return window_start; }
    public void setWindow_start(Long window_start) { this.window_start = window_start; }
    
    public Long getWindow_end() { return window_end; }
    public void setWindow_end(Long window_end) { this.window_end = window_end; }
    
    // Inner classes for nested structures
    public static class Cancelamento {
        private String id_cancelamento;
        private String data_cancelamento;
        private Double valor_cancelado;
        private String motivo;
        
        public String getId_cancelamento() { return id_cancelamento; }
        public void setId_cancelamento(String id_cancelamento) { this.id_cancelamento = id_cancelamento; }
        
        public String getData_cancelamento() { return data_cancelamento; }
        public void setData_cancelamento(String data_cancelamento) { 
            this.data_cancelamento = data_cancelamento; 
        }
        
        public Double getValor_cancelado() { return valor_cancelado; }
        public void setValor_cancelado(Double valor_cancelado) { this.valor_cancelado = valor_cancelado; }
        
        public String getMotivo() { return motivo; }
        public void setMotivo(String motivo) { this.motivo = motivo; }
    }
    
    public static class Negociacao {
        private String id_negociacao;
        private String data_negociacao;
        private Double valor_negociado;
        
        public String getId_negociacao() { return id_negociacao; }
        public void setId_negociacao(String id_negociacao) { this.id_negociacao = id_negociacao; }
        
        public String getData_negociacao() { return data_negociacao; }
        public void setData_negociacao(String data_negociacao) { this.data_negociacao = data_negociacao; }
        
        public Double getValor_negociado() { return valor_negociado; }
        public void setValor_negociado(Double valor_negociado) { this.valor_negociado = valor_negociado; }
    }
}
