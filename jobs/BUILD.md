# Como Criar e Executar o Job no Apache Flink

## Pré-requisitos

- Java 11 instalado
- Maven instalado
- Docker Compose em execução (com Flink, Kafka, DynamoDB, Elasticsearch)

## Passo 1: Criar Estrutura do Projeto

```powershell
# No diretório jobs/
mkdir flink-generic-aggregator
cd flink-generic-aggregator

# Criar estrutura de diretórios
mkdir -p src/main/java/com/aggregator/functions
mkdir -p src/main/java/com/aggregator/models
mkdir -p src/main/resources
```

## Passo 2: Criar Arquivos do Projeto

Copie todo o conteúdo do arquivo `IMPLEMENTATION.md` e crie os seguintes arquivos na estrutura:

### pom.xml
Na raiz de `flink-generic-aggregator/`

### src/main/java/com/aggregator/GenericEventAggregator.java
Classe principal do job

### src/main/java/com/aggregator/functions/
- JsonPathExtractor.java
- EventAggregator.java
- DynamoDBEventWriter.java
- DynamoDBEnricher.java
- ElasticsearchSink.java

### src/main/java/com/aggregator/models/
- EventWithId.java
- AggregationResult.java
- EnrichedAggregation.java

### src/main/resources/application.json
Configuração do job

## Passo 3: Compilar o Projeto

```powershell
# No diretório flink-generic-aggregator/
mvn clean package
```

Isso irá gerar o arquivo JAR em:
```
target/flink-generic-aggregator-1.0.0.jar
```

## Passo 4: Copiar JAR para o Flink

Você tem 3 opções:

### Opção A: Via Interface Web (Recomendado)

1. Acesse http://localhost:8081
2. Clique em "Submit New Job" no menu lateral
3. Clique em "+ Add New" para fazer upload do JAR
4. Selecione o arquivo `target/flink-generic-aggregator-1.0.0.jar`
5. Após upload, clique no JAR na lista
6. Clique em "Submit" para executar

### Opção B: Via Docker CLI

```powershell
# Copiar JAR para o container
docker cp target/flink-generic-aggregator-1.0.0.jar flink-jobmanager:/opt/flink/usrlib/

# Submeter o job
docker exec flink-jobmanager flink run `
  -d `
  -c com.aggregator.GenericEventAggregator `
  /opt/flink/usrlib/flink-generic-aggregator-1.0.0.jar
```

### Opção C: Via Volume Montado

Adicione no `docker-compose.yml` (seção jobmanager):

```yaml
volumes:
  - ./jobs/flink-generic-aggregator/target:/opt/flink/usrlib
```

Depois execute:
```powershell
docker compose restart flink-jobmanager

docker exec flink-jobmanager flink run `
  -d `
  -c com.aggregator.GenericEventAggregator `
  /opt/flink/usrlib/flink-generic-aggregator-1.0.0.jar
```

## Passo 5: Verificar Execução

### Via Interface Web
1. Acesse http://localhost:8081
2. Clique em "Running Jobs"
3. Você verá o job "Generic Event Aggregator" executando

### Via CLI
```powershell
docker exec flink-jobmanager flink list -r
```

## Passo 6: Testar o Pipeline

```powershell
# 1. Enviar eventos para o Kafka (usando o producer Go)
cd ../producer
.\producer.exe -count 100

# 2. Verificar eventos no DynamoDB
# Acesse: http://localhost:8001
# Selecione a tabela "Recebiveis"

# 3. Verificar agregações no Elasticsearch
curl http://localhost:9200/agregacoes-finais/_search?pretty
```

## Troubleshooting

### Job falha ao iniciar

**Erro de conexão Kafka:**
```powershell
# Verificar se Kafka está acessível
docker exec kafka kafka-topics --list --bootstrap-server localhost:29092
```

**Erro de conexão DynamoDB:**
```powershell
# Verificar se DynamoDB está respondendo
aws dynamodb list-tables --endpoint-url http://localhost:8000 --region us-east-1
```

**Erro de conexão Elasticsearch:**
```powershell
# Verificar se Elasticsearch está respondendo
curl http://localhost:9200
```

### Ver logs do job

```powershell
# Logs do JobManager
docker logs flink-jobmanager

# Logs dos TaskManagers
docker logs apacheflink-taskmanager-1
docker logs apacheflink-taskmanager-2
```

### Cancelar job em execução

```powershell
# Via Interface Web: http://localhost:8081 > Running Jobs > Cancel

# Via CLI
docker exec flink-jobmanager flink list -r
docker exec flink-jobmanager flink cancel <JOB_ID>
```

### Recompilar após mudanças

```powershell
# 1. Cancelar job atual (se estiver rodando)
# 2. Recompilar
mvn clean package

# 3. Resubmeter
docker exec flink-jobmanager flink run -d -c com.aggregator.GenericEventAggregator /opt/flink/usrlib/flink-generic-aggregator-1.0.0.jar
```

## Monitoramento

- **Flink Dashboard**: http://localhost:8081
- **Kafka UI**: http://localhost:8090
- **DynamoDB Admin**: http://localhost:8001
- **Elasticsearch**: http://localhost:9200

## Próximos Passos

1. Ajustar `application.json` conforme necessário (window size, batch size, etc.)
2. Monitorar checkpoints e backpressure no Flink Dashboard
3. Validar dados no DynamoDB e Elasticsearch
4. Ajustar paralelismo se necessário
