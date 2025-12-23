# Pipeline de Agregação com Kafka, Apache Flink e Elasticsearch

## Arquitetura

```
Produtor → Kafka → Apache Flink → Elasticsearch
```

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

## Como Usar

### Iniciar a Pipeline (Automatizado)

**Windows**:
```bash
start.bat
```

**Linux/Mac**:
```bash
chmod +x start.sh init-kafka.sh init-dynamodb.sh
./start.sh
```

O script automatizado irá:
1. Subir todos os containers
2. Aguardar inicialização dos serviços
3. Criar tópicos no Kafka:
   - `recebiveis-eventos` (3 partições, 7 dias retenção)
   - `recebiveis-cancelamentos` (2 partições, 30 dias retenção)
   - `recebiveis-negociacoes` (2 partições, 30 dias retenção)
   - `recebiveis-agregados` (3 partições, 24h retenção)
4. Criar tabela `Recebiveis` no DynamoDB com índices GSI

### Iniciar Manualmente

```bash
# 1. Subir containers
docker-compose up -d

# 2. Aguardar ~30 segundos

# 3. Criar tópicos Kafka
bash init-kafka.sh

# 4. Criar tabelas DynamoDB
bash init-dynamodb.sh
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
