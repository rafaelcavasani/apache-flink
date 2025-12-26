# Pipeline de Agregação com Kafka, Apache Flink e Elasticsearch

## Arquitetura

```
Produtor → Kafka → Apache Flink/Spark → DynamoDB + Elasticsearch
```

## 🚀 Quick Start - Executando o Projeto

Este projeto utiliza um **Makefile** para simplificar a execução. Siga os passos abaixo para iniciar e validar o pipeline completo:

### 1️⃣ Subir a Infraestrutura

Primeiro, inicie todos os serviços Docker (Kafka, Elasticsearch, DynamoDB, Flink/Spark):

```bash
make services
```

Este comando iniciará:
- **Kafka** (broker de mensagens) - http://localhost:8090 (UI)
- **Elasticsearch** (storage de agregações) - http://localhost:9200
- **DynamoDB Local** (storage de eventos) - http://localhost:8001 (Admin)
- **Zookeeper** (coordenação do Kafka)

⏱️ **Aguarde ~30 segundos** para os serviços ficarem prontos.

---

### 2️⃣ Inicializar Recursos

Crie os tópicos no Kafka, tabela no DynamoDB e índice no Elasticsearch:

```bash
make init
```

Este comando executa:
- `make init-kafka` - Cria tópicos: `recebiveis-agendados`, `recebiveis-cancelados`, `recebiveis-negociados`
- `make init-db` - Cria tabela `Recebiveis` no DynamoDB com GSI `ClienteIndex`
- `make init-es` - Cria índice `ciclo_vida_recebiveis` no Elasticsearch

✅ Após este passo, a infraestrutura está pronta para receber eventos!

---

### 3️⃣ Executar o Job de Processamento

Escolha entre **Flink** ou **Spark** para processar os eventos:

#### Opção A: Apache Flink

```bash
make flink-job
```

Este comando:
1. Compila o job Flink (`mvn clean package`)
2. Submete o JAR para o Flink JobManager
3. Inicia o processamento stream em tempo real

📊 **Acesse o dashboard**: http://localhost:8081

#### Opção B: Apache Spark Streaming

```bash
make spark-job
```

Este comando:
1. Inicia o cluster Spark (Master + Workers)
2. Executa o job de streaming com micro-batches
3. Processa eventos a cada 15 segundos

📊 **Acesse o dashboard**: http://localhost:8082

---

### 4️⃣ Enviar Eventos de Teste

Execute o producer Go para gerar eventos simulados no Kafka:

```bash
make producer
```

Este comando envia **100 eventos** simulando o ciclo de vida de recebíveis:
- **AGENDADO**: Criação de novo recebível
- **CANCELADO**: Cancelamento de recebível
- **NEGOCIADO**: Negociação/liquidação antecipada

Os eventos serão processados pelo job (Flink ou Spark) e armazenados em:
- **DynamoDB**: Eventos brutos individuais
- **Elasticsearch**: Dados agregados por janela de tempo (15 segundos)

---

### 5️⃣ Validar Resultados

Verifique se os dados foram processados corretamente:

```bash
make validate
```

Este comando:
1. Compara dados entre DynamoDB e Elasticsearch
2. Valida consistência de `id_recebivel`
3. Verifica cálculos de agregação (`valor_disponivel`)
4. Gera relatório de validação

✅ **Resultado esperado**: Todos os IDs encontrados em ambos os storages com valores consistentes.

---

### 📋 Comandos Adicionais Úteis

```bash
# Ver status de todos os serviços
make status

# Contar documentos no Elasticsearch
make es-count

# Contar itens no DynamoDB
make dynamodb-count

# Listar tópicos Kafka
make kafka-topics

# Ver logs do job Spark
make spark-logs

# Ver logs do job Flink
docker-compose logs -f jobmanager

# Parar job Spark
make spark-stop

# Cancelar jobs Flink
make flink-cancel

# Reiniciar tudo
make restart

# Parar todos os serviços
make down

# Limpeza completa (remove volumes)
make clean
```

---

### 🧪 Pipeline Completo de Teste

Execute o fluxo completo automaticamente:

**Com Flink:**
```bash
make test-flink
```

**Com Spark:**
```bash
make test-spark
```

Estes comandos executam sequencialmente: `init` → `job` → `producer` → `validate`

---

## Componentes

### 1. **Kafka** (Broker de Mensagens)
- **Porta**: 9092 (host), 29092 (inter-container)
- **Função**: Recebe e armazena eventos em tópicos
- **Kafka UI**: http://localhost:8090

### 2. **Apache Flink** (Processamento de Stream)
- **JobManager**: http://localhost:8081
- **TaskManagers**: 2 instâncias com 4 slots cada
- **Função**: Processa streams do Kafka e agrega dados

### 3. **Elasticsearch** (Storage & Search)
- **Porta**: 9200
- **Função**: Armazena dados agregados para consultas

### 4. **DynamoDB Local** (NoSQL Database)
- **Porta**: 8000
- **DynamoDB Admin**: http://localhost:8001
- **Função**: Storage NoSQL para dados transacionais
- **Credenciais**: `AWS_ACCESS_KEY_ID=local`, `AWS_SECRET_ACCESS_KEY=local`

### 5. **Zookeeper**
- **Porta**: 2181
- **Função**: Coordenação do cluster Kafka

## Detalhes dos Componentes

### Tópicos Kafka
- `recebiveis-agendados` (3 partições, 7 dias retenção)
- `recebiveis-cancelados` (2 partições, 30 dias retenção)
- `recebiveis-negociados` (2 partições, 30 dias retenção)

### Tabela DynamoDB
- **Nome**: `Recebiveis`
- **Chave primária**: `id_recebivel` (String)
- **GSI**: `ClienteIndex` com `codigo_cliente` como chave de partição

### Índice Elasticsearch
- **Nome**: `ciclo_vida_recebiveis`
- **Campos agregados**: `id_recebivel`, `codigo_cliente`, `valor_disponivel`, `ultima_atualizacao`

---

## Modo Manual (Alternativo)

Se preferir executar sem o Makefile:

```bash
# 1. Subir containers
docker-compose up -d

# 2. Aguardar ~30 segundos

# 3. Criar recursos
cd scripts
pwsh -File init-kafka.ps1
pwsh -File init-dynamodb.ps1
pwsh -File init-elasticsearch.ps1

# 4. Executar job
make flink-job  # ou make spark-job

# 5. Enviar eventos
cd producer && go run main.go -count 100 -interval 10ms

# 6. Validar
cd scripts && pwsh -File validate-data-consistency.ps1
```

### Verificar Status dos Serviços

```bash
docker-compose ps
```

### Acessar Interfaces Web

- **Flink Dashboard**: http://localhost:8081
- **Kafka UI**: http://localhost:8090
- **Elasticsearch**: http://localhost:9200
- **DynamoDB Admin**: http://localhost:8001

### Criar Tópico no Kafka

```bash
docker exec -it kafka kafka-topics --create \
  --topic meu-topico \
  --bootstrap-server localhost:29092 \
  --partitions 3 \
  --replication-factor 1
```

**Nota**: Tópicos principais já são criados automaticamente pelo `init-kafka.sh`

### Listar Tópicos

```bash
docker exec -it kafka kafka-topics --list \
  --bootstrap-server localhost:29092
```

### Produzir Mensagens de Teste

```bash
docker exec -it kafka kafka-console-producer \
  --topic recebiveis-eventos \
  --bootstrap-server localhost:29092
```

### Consumir Mensagens

```bash
docker exec -it kafka kafka-console-consumer \
  --topic recebiveis-eventos \
  --bootstrap-server localhost:29092 \
  --from-beginning
```

## Exemplo de Job Flink

Coloque seus JARs de jobs Flink na pasta `./jobs/` e eles estarão disponíveis em `/opt/flink/usrlib` dentro dos containers.

### Estrutura de Dados Sugerida

**Evento de Recebível (Kafka)**:
```json
{
  "id_recebivel": "REC-001",
  "codigo_cliente": "CLI-10001",
  "valor_original": 1000.00,
  "data_vencimento": "2025-12-31",
  "tipo_evento": "criacao",
  "timestamp": "2025-12-23T10:00:00Z"
}
```

**Agregação (Flink → Elasticsearch)**:
```json
{
  "codigo_cliente": "CLI-10001",
  "total_recebiveis": 150,
  "soma_valores": 150000.00,
  "media_valor": 1000.00,
  "janela_tempo": "2025-12-23T10:00:00Z"
}
```

## Parar a Pipeline

```bash
docker-compose down
```

## Remover Volumes (Reset Completo)

```bash
docker-compose down -v
```

## Logs

### Ver logs de um serviço específico
```bash
docker-compose logs -f kafka
docker-compose logs -f jobmanager
docker-compose logs -f elasticsearch
```

## Troubleshooting

### Kafka não conecta
- Verifique se Zookeeper está rodando: `docker-compose ps zookeeper`
- Aguarde ~30 segundos após iniciar para Kafka ficar pronto

### Flink não submete jobs
- Verifique se JobManager está rodando: `curl http://localhost:8081`
- Verifique TaskManagers conectados no dashboard

### Elasticsearch não responde
- Aguarde ~1 minuto após iniciar
- Teste: `curl http://localhost:9200/_cluster/health`

### DynamoDB Local

**Nota**: A tabela `Recebiveis` já é criada automaticamente pelo `init-dynamodb.sh`

#### Criar Tabela Adicional
```bash
aws dynamodb create-table \
  --table-name Recebiveis \
  --attribute-definitions \
      AttributeName=id_recebivel,AttributeType=S \
      AttributeName=codigo_cliente,AttributeType=S \
  --key-schema \
      AttributeName=id_recebivel,KeyType=HASH \
  --global-secondary-indexes \
      IndexName=ClienteIndex,KeySchema=[{AttributeName=codigo_cliente,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

#### Listar Tabelas
```bash
aws dynamodb list-tables --endpoint-url http://localhost:8000 --region us-east-1
```

#### Inserir Item
```bash
aws dynamodb put-item \
  --table-name Recebiveis \
  --item '{"id_recebivel":{"S":"REC-001"},"codigo_cliente":{"S":"CLI-10001"},"valor_original":{"N":"1000"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

#### Consultar Item
```bash
aws dynamodb get-item \
  --table-name Recebiveis \
  --key '{"id_recebivel":{"S":"REC-001"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

**Nota**: Configure AWS CLI com credenciais dummy: `aws configure` e use `local`/`local`

## Próximos Passos

1. Criar job Flink para ler do Kafka
2. Implementar lógica de agregação (windowing)
3. Configurar sink para Elasticsearch
4. Configurar checkpointing para tolerância a falhas
