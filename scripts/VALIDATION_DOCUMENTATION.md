# Documentação do Script de Validação de Consistência

## Visão Geral

O script `validate-data-consistency.ps1` realiza validações completas de consistência de dados entre **DynamoDB** (fonte de eventos) e **Elasticsearch** (agregações processadas pelo Flink). O objetivo é garantir que todas as agregações foram calculadas corretamente e que nenhum dado foi perdido ou corrompido durante o pipeline de processamento.

## Arquitetura do Pipeline

```
Producer (Go) → Kafka → Flink Job → DynamoDB Writer
                          ↓
                    Window Aggregation
                          ↓
                    DynamoDB Enricher → Elasticsearch
```

## Campos Verificados

### Campos do Elasticsearch (Agregação)

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id_recebivel` | String (keyword) | Identificador único do recebível |
| `id_pagamento` | String (keyword) | Identificador do pagamento associado |
| `codigo_produto` | Integer | Código do produto |
| `codigo_produto_parceiro` | Integer | Código do produto do parceiro |
| `modalidade` | Integer | Modalidade do recebível |
| `valor_original` | Double | Valor original do recebível (do evento agendado) |
| `valor_disponivel` | Double | Valor disponível após cancelamentos e negociações |
| `valor_total_cancelado` | Double | Soma de todos os valores cancelados |
| `valor_total_negociado` | Double | Soma de todos os valores negociados |
| `data_vencimento` | String (date) | Data de vencimento do recebível |
| `quantidade_eventos` | Integer | Total de eventos recebidos para este ID |
| `quantidade_cancelamentos` | Integer | Quantidade de eventos tipo "cancelado" |
| `quantidade_negociacoes` | Integer | Quantidade de eventos tipo "negociado" |
| `cancelamentos` | Array | Array de objetos com detalhes de cada cancelamento |
| `negociacoes` | Array | Array de objetos com detalhes de cada negociação |
| `timestamp` | String | Timestamp do primeiro evento (agendado) |
| `window_start` | Long | Timestamp do início da janela de agregação |
| `window_end` | Long | Timestamp do fim da janela de agregação |

### Campos do DynamoDB (Eventos Brutos)

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id_recebivel` | String (S) | Partition Key - Identificador do recebível |
| `tipo_evento` | String (S) | Sort Key - Tipo do evento (agendado/cancelado/negociado) |
| `timestamp` | String (S) | Timestamp do evento |
| `id_pagamento` | String (S) | Identificador do pagamento |
| `codigo_produto` | Number (N) | Código do produto |
| `codigo_produto_parceiro` | Number (N) | Código do produto do parceiro |
| `modalidade` | Number (N) | Modalidade do recebível |
| `valor_original` | Number (N) | Valor original (apenas em eventos "agendado") |
| `data_vencimento` | String (S) | Data de vencimento (apenas em eventos "agendado") |
| `id_cancelamento` | String (S) | ID do cancelamento (apenas em eventos "cancelado") |
| `data_cancelamento` | String (S) | Data do cancelamento (apenas em eventos "cancelado") |
| `valor_cancelado` | Number (N) | Valor cancelado (apenas em eventos "cancelado") |
| `motivo` | String (S) | Motivo do cancelamento (apenas em eventos "cancelado") |
| `id_negociacao` | String (S) | ID da negociação (apenas em eventos "negociado") |
| `data_negociacao` | String (S) | Data da negociação (apenas em eventos "negociado") |
| `valor_negociado` | Number (N) | Valor negociado (apenas em eventos "negociado") |

## Validações Realizadas

O script executa **7 validações críticas** para cada agregação:

### 1. Validação de Total de Eventos

**Objetivo:** Garantir que todos os eventos enviados pelo Kafka foram contabilizados na agregação.

**Verificação:**
```
ES.quantidade_eventos === DynamoDB.Count(todos os eventos)
```

**Detalhes:**
- Conta todos os eventos no DynamoDB para o `id_recebivel`
- Compara com o campo `quantidade_eventos` do Elasticsearch
- **Falha se:** Os valores forem diferentes

**Exemplo de Erro:**
```
Divergência no total de eventos: ES=2 vs DynamoDB=3
```

---

### 2. Validação de Quantidade de Cancelamentos

**Objetivo:** Verificar se todos os eventos de cancelamento foram identificados e contabilizados.

**Verificação:**
```
ES.quantidade_cancelamentos === DynamoDB.Count(eventos tipo "cancelado")
```

**Detalhes:**
- Filtra eventos onde `tipo_evento = "cancelado"` no DynamoDB
- Compara a contagem com `quantidade_cancelamentos` do Elasticsearch
- **Falha se:** As quantidades não coincidirem

**Exemplo de Erro:**
```
Divergência em cancelamentos: ES=0 vs DynamoDB=1
```

---

### 3. Validação de Quantidade de Negociações

**Objetivo:** Verificar se todos os eventos de negociação foram identificados e contabilizados.

**Verificação:**
```
ES.quantidade_negociacoes === DynamoDB.Count(eventos tipo "negociado")
```

**Detalhes:**
- Filtra eventos onde `tipo_evento = "negociado"` no DynamoDB
- Compara a contagem com `quantidade_negociacoes` do Elasticsearch
- **Falha se:** As quantidades não coincidirem

**Exemplo de Erro:**
```
Divergência em negociações: ES=0 vs DynamoDB=1
```

---

### 4. Validação de Valor Original

**Objetivo:** Garantir que o valor base do recebível foi capturado corretamente do evento inicial.

**Verificação:**
```
ES.valor_original === DynamoDB.evento_agendado.valor_original
```

**Detalhes:**
- Localiza o evento tipo "agendado" no DynamoDB
- Extrai o campo `valor_original` (Number)
- Compara com o campo `valor_original` do Elasticsearch
- **Falha se:** Os valores forem diferentes ou se `valor_original` estiver null/vazio no ES

**Exemplo de Erro:**
```
Divergência no valor original: ES= vs DynamoDB=10000
```

---

### 5. Validação de Soma de Cancelamentos

**Objetivo:** Verificar se a soma de todos os valores cancelados está correta.

**Verificação:**
```
|ES.valor_total_cancelado - SUM(DynamoDB.valores_cancelados)| <= 0.01
```

**Detalhes:**
- Soma todos os campos `valor_cancelado` dos eventos "cancelado" no DynamoDB
- Compara com o campo `valor_total_cancelado` do Elasticsearch
- **Tolerância:** ±R$ 0,01 para compensar arredondamentos de ponto flutuante
- **Falha se:** A diferença absoluta for maior que 0.01

**Exemplo de Erro:**
```
Divergência no total cancelado: ES=0 vs DynamoDB=10000
```

---

### 6. Validação de Soma de Negociações

**Objetivo:** Verificar se a soma de todos os valores negociados está correta.

**Verificação:**
```
|ES.valor_total_negociado - SUM(DynamoDB.valores_negociados)| <= 0.01
```

**Detalhes:**
- Soma todos os campos `valor_negociado` dos eventos "negociado" no DynamoDB
- Compara com o campo `valor_total_negociado` do Elasticsearch
- **Tolerância:** ±R$ 0,01 para compensar arredondamentos de ponto flutuante
- **Falha se:** A diferença absoluta for maior que 0.01

**Exemplo de Erro:**
```
Divergência no total negociado: ES=0 vs DynamoDB=3252.24
```

---

### 7. Validação de Tamanho dos Arrays

**Objetivo:** Garantir que todos os detalhes dos eventos foram preservados nos arrays de cancelamentos e negociações.

**Verificação:**
```
ES.cancelamentos.length === DynamoDB.Count(eventos "cancelado")
ES.negociacoes.length === DynamoDB.Count(eventos "negociado")
```

**Detalhes:**
- Verifica se o array `cancelamentos[]` no ES tem o mesmo tamanho que a quantidade de eventos "cancelado" no DynamoDB
- Verifica se o array `negociacoes[]` no ES tem o mesmo tamanho que a quantidade de eventos "negociado" no DynamoDB
- **Falha se:** Os tamanhos não coincidirem

**Exemplo de Erro:**
```
Divergência no array de cancelamentos: ES=0 itens vs DynamoDB=1 eventos
Divergência no array de negociações: ES=0 itens vs DynamoDB=1 eventos
```

---

## Estrutura dos Arrays no Elasticsearch

### Array de Cancelamentos

Cada item no array `cancelamentos[]` contém:
```json
{
  "id_cancelamento": "uuid",
  "data_cancelamento": "YYYY-MM-DD",
  "valor_cancelado": 1000.50,
  "motivo": "Cliente solicitou cancelamento"
}
```

### Array de Negociações

Cada item no array `negociacoes[]` contém:
```json
{
  "id_negociacao": "uuid",
  "data_negociacao": "YYYY-MM-DD",
  "valor_negociado": 2500.75
}
```

---

## Execução do Script

### Sintaxe Básica

```powershell
# Validar 20 IDs aleatórios (padrão)
.\scripts\validate-data-consistency.ps1

# Validar IDs específicos
.\scripts\validate-data-consistency.ps1 -ReceivableIds @("id1", "id2", "id3")
```

### Parâmetros

| Parâmetro | Tipo | Descrição | Padrão |
|-----------|------|-----------|--------|
| `-ReceivableIds` | String[] | Array de IDs específicos para validar | Busca 50 IDs aleatórios do ES |

### Saída do Script

O script exibe no console:
- Status de cada validação (✅ OK ou ❌ ERRO)
- Detalhes de cada campo verificado
- Lista de erros encontrados
- Resumo final com estatísticas

E salva os resultados em:
```
./performance_test/validation_results_YYYYMMDD_HHMMSS.json
```

---

## Formato do Arquivo de Resultados

```json
[
  {
    "id_recebivel": "uuid",
    "elasticsearch_exists": true,
    "dynamodb_events": 3,
    "consistency_check": "OK",
    "errors": [],
    "details": {
      "es_quantidade_eventos": 3,
      "dynamo_total_eventos": 3,
      "es_quantidade_cancelamentos": 1,
      "dynamo_cancelamentos": 1,
      "es_quantidade_negociacoes": 1,
      "dynamo_negociacoes": 1
    }
  },
  {
    "id_recebivel": "uuid",
    "elasticsearch_exists": true,
    "dynamodb_events": 2,
    "consistency_check": "ERROR",
    "errors": [
      "Divergência em cancelamentos: ES=0 vs DynamoDB=1",
      "Divergência no total cancelado: ES=0 vs DynamoDB=10000"
    ],
    "details": {
      "es_quantidade_eventos": 2,
      "dynamo_total_eventos": 2,
      "es_quantidade_cancelamentos": 0,
      "dynamo_cancelamentos": 1,
      "es_quantidade_negociacoes": 0,
      "dynamo_negociacoes": 0
    }
  }
]
```

---

## Interpretação dos Resultados

### ✅ Validação Bem-Sucedida

**Critérios:**
- Todas as 7 validações passaram
- `consistency_check = "OK"`
- Array `errors` vazio

**Significado:**
- Os dados estão 100% consistentes entre DynamoDB e Elasticsearch
- A agregação foi calculada corretamente
- Nenhum dado foi perdido ou corrompido

### ❌ Validação com Erro

**Possíveis Causas:**
1. **Race Condition:** Eventos ainda não foram escritos no DynamoDB quando o enricher foi executado
2. **Bug no DynamoDBEnricher:** Lógica de agregação com erro
3. **Bug no DynamoDBEventWriter:** Eventos não foram salvos no DynamoDB
4. **Perda de Dados:** Eventos perdidos no Kafka ou no pipeline

**Ações Recomendadas:**
1. Verificar logs do Flink Job (buscar por `[WRITER]` e `[ENRICH]`)
2. Verificar se o batch size do DynamoDBEventWriter está configurado corretamente (deve ser 1 para evitar race conditions)
3. Verificar se há erros no Kafka ou no DynamoDB
4. Re-executar a validação após aguardar alguns segundos (pode ser timing)

---

## Métricas de Sucesso

### Taxa de Sucesso Esperada

- **Ambiente Local:** ≥ 95%
- **Ambiente de Produção:** ≥ 99%

### Histórico de Testes

| Data | Total IDs | Sucesso | Taxa |
|------|-----------|---------|------|
| 2025-12-24 17:42 | 20 | 20 | 100% |
| 2025-12-24 16:55 | 20 | 16 | 80% |

**Nota:** O teste de 16:55 tinha bugs que foram corrigidos (batch size do writer era 25, causando race conditions).

---

## Casos de Uso

### 1. Validação Pós-Deploy

Após fazer deploy de uma nova versão do Flink Job:
```powershell
# Enviar eventos de teste
cd producer
go run main.go --count 100

# Aguardar processamento (2x o tempo da janela)
Start-Sleep -Seconds 30

# Validar
cd ..
.\scripts\validate-data-consistency.ps1
```

### 2. Debug de Inconsistências

Quando encontrar agregações suspeitas:
```powershell
# Validar IDs específicos
$ids = @(
    "uuid-problema-1",
    "uuid-problema-2",
    "uuid-problema-3"
)
.\scripts\validate-data-consistency.ps1 -ReceivableIds $ids
```

### 3. Teste de Performance

Validar dados após teste de carga:
```powershell
# Coletar 50 IDs aleatórios e validar
.\scripts\validate-data-consistency.ps1

# Analisar resultados
$results = Get-Content .\performance_test\validation_results_*.json | ConvertFrom-Json
$errors = $results | Where-Object { $_.consistency_check -eq 'ERROR' }
Write-Host "Taxa de erro: $($errors.Count / $results.Count * 100)%"
```

---

## Troubleshooting

### Erro: "Sem eventos no DynamoDB"

**Causa:** O ID existe no Elasticsearch mas não no DynamoDB.

**Possíveis Razões:**
- DynamoDBEventWriter não salvou o evento
- Tabela do DynamoDB foi recriada após o processamento
- Query no DynamoDB falhou

**Solução:**
- Verificar logs do DynamoDBEventWriter
- Confirmar que a tabela existe: `aws dynamodb list-tables --endpoint-url http://localhost:8000`

### Erro: "Divergência no valor original"

**Causa:** O valor do campo `valor_original` está diferente ou null no ES.

**Possíveis Razões:**
- Evento "agendado" não foi processado corretamente
- DynamoDBEnricher não encontrou o evento "agendado" no DynamoDB
- Parsing incorreto do campo Number

**Solução:**
- Verificar se o evento "agendado" existe no DynamoDB
- Adicionar logging no DynamoDBEnricher para debug

### Erro: "Divergência no array de cancelamentos"

**Causa:** O array `cancelamentos[]` está vazio mas existem eventos "cancelado" no DynamoDB.

**Possíveis Razões:**
- Bug no DynamoDBEnricher ao construir o array
- Race condition: evento cancelado chegou depois do enriquecimento

**Solução:**
- Verificar lógica de construção do array no DynamoDBEnricher.java (linhas 122-143)
- Confirmar se o batch size está configurado como 1

---

## Referências

- Script: `./scripts/validate-data-consistency.ps1`
- Flink Job Enricher: `./flinkjob/src/main/java/com/aggregator/functions/DynamoDBEnricher.java`
- Flink Job Writer: `./flinkjob/src/main/java/com/aggregator/functions/DynamoDBEventWriter.java`
- Producer: `./producer/main.go`

---

## Changelog

| Versão | Data | Mudanças |
|--------|------|----------|
| 1.0 | 2025-12-24 | Versão inicial com 7 validações |
| 1.1 | 2025-12-24 | Modificado para buscar 50 IDs (antes era 20) |
