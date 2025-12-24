# Makefile - Guia de Comandos

Este Makefile fornece comandos convenientes para gerenciar todo o ambiente de agregação de recebíveis, incluindo Flink e Spark.

## 📋 Listar Comandos Disponíveis

```bash
make help
```

## 🚀 Início Rápido

### 1. Iniciar Infraestrutura

```bash
# Iniciar todos os serviços (Kafka, Elasticsearch, DynamoDB, Flink, Spark)
make up

# Aguardar serviços iniciarem (30 segundos)
sleep 30

# Inicializar recursos (tópicos Kafka, tabelas, índices)
make init
```

### 2. Executar com Flink

```bash
# Compilar e executar job Flink
make flink-job

# Gerar eventos de teste
make producer

# Validar resultados
make validate
```

### 3. Executar com Spark

```bash
# Iniciar job Spark
make spark-job

# Gerar eventos de teste
make producer

# Validar resultados
make validate

# Parar job Spark
make spark-stop
```

## 📚 Comandos Detalhados

### Gerenciamento de Containers

| Comando | Descrição |
|---------|-----------|
| `make up` | Inicia todos os serviços |
| `make down` | Para todos os serviços |
| `make restart` | Reinicia todos os serviços |
| `make clean` | Remove containers e volumes |
| `make logs` | Mostra logs de todos os serviços |
| `make status` | Mostra status dos serviços |

### Jobs Flink

| Comando | Descrição |
|---------|-----------|
| `make flink-build` | Compila o job Flink (Maven) |
| `make flink-job` | Submete o job Flink para execução |
| `make flink-list` | Lista todos os jobs Flink |
| `make flink-cancel` | Cancela jobs Flink em execução |

### Jobs Spark

| Comando | Descrição |
|---------|-----------|
| `make spark-job` | Inicia o job Spark no cluster |
| `make spark-stop` | Para o job Spark |
| `make spark-logs` | Mostra logs do job Spark |
| `make spark-local` | Executa Spark localmente (fora do Docker) |

### Inicialização de Dados

| Comando | Descrição |
|---------|-----------|
| `make init` | Inicializa todos os recursos (recomendado) |
| `make init-kafka` | Cria tópicos no Kafka |
| `make init-db` | Cria tabela no DynamoDB |
| `make init-es` | Cria índice no Elasticsearch |

### Testes e Validação

| Comando | Descrição |
|---------|-----------|
| `make producer` | Gera 100 eventos de teste |
| `make producer-continuous` | Gera eventos continuamente (2 min) |
| `make validate` | Valida consistência DynamoDB ↔ Elasticsearch |
| `make test-flink` | Pipeline completo de teste com Flink |
| `make test-spark` | Pipeline completo de teste com Spark |

### Utilitários

| Comando | Descrição |
|---------|-----------|
| `make kafka-topics` | Lista tópicos Kafka |
| `make es-count` | Conta documentos no Elasticsearch |
| `make dynamodb-count` | Conta itens no DynamoDB |
| `make shell-flink` | Abre shell no Flink JobManager |
| `make shell-spark` | Abre shell no Spark Master |
| `make shell-kafka` | Abre shell no Kafka |

## 🔧 Exemplos de Uso

### Teste Completo com Flink

```bash
# Pipeline completo automatizado
make test-flink

# Ou passo a passo:
make up
make init
make flink-job
make producer
sleep 30
make validate
```

### Teste Completo com Spark

```bash
# Pipeline completo automatizado
make test-spark

# Ou passo a passo:
make up
make init
make spark-job
make producer
sleep 30
make validate
make spark-stop
```

### Comparar Flink vs Spark

```bash
# Testar Flink
make up && make init
make flink-job
make producer-continuous
make validate

# Parar Flink e testar Spark
make flink-cancel
make clean && make up && make init
make spark-job
make producer-continuous
make validate
make spark-stop
```

### Desenvolvimento Iterativo

```bash
# 1. Fazer alterações no código
# 2. Recompilar Flink
make flink-build

# 3. Cancelar job antigo
make flink-cancel

# 4. Submeter novo job
make flink-job

# Ou para Spark (não precisa compilar)
make spark-stop
make spark-job
```

### Monitoramento Contínuo

```bash
# Terminal 1: Logs do job
make spark-logs  # ou docker-compose logs -f jobmanager

# Terminal 2: Producer contínuo
while true; do make producer; sleep 5; done

# Terminal 3: Monitorar contagens
watch -n 2 'make es-count'
```

## 🌐 URLs dos Serviços

Após `make up`, os seguintes serviços estarão disponíveis:

| Serviço | URL | Descrição |
|---------|-----|-----------|
| Kafka UI | http://localhost:8090 | Interface web para Kafka |
| Elasticsearch | http://localhost:9200 | API REST do Elasticsearch |
| DynamoDB Admin | http://localhost:8001 | Interface web para DynamoDB |
| Flink Dashboard | http://localhost:8081 | Dashboard do Flink |
| Spark UI | http://localhost:8082 | Interface web do Spark |

## 🐛 Troubleshooting

### Jobs não aparecem no Flink

```bash
# Verificar se JobManager está rodando
docker ps | grep flink

# Ver logs do JobManager
docker logs flink-jobmanager

# Listar jobs
make flink-list
```

### Spark job não inicia

```bash
# Ver logs detalhados
make spark-logs

# Verificar se Spark Master está rodando
docker ps | grep spark

# Reiniciar serviços Spark
docker-compose restart spark-master spark-worker
make spark-job
```

### Kafka não conecta

```bash
# Verificar tópicos
make kafka-topics

# Reinicializar Kafka
docker-compose restart kafka zookeeper
sleep 10
make init-kafka
```

### Elasticsearch não responde

```bash
# Verificar saúde do cluster
curl http://localhost:9200/_cluster/health?pretty

# Recriar índice
curl -X DELETE http://localhost:9200/ciclo_vida_recebiveis
make init-es
```

### DynamoDB vazio

```bash
# Verificar tabela
aws dynamodb describe-table --table-name Recebiveis \
  --endpoint-url http://localhost:8000 --region us-east-1

# Recriar tabela
make init-db
```

## 📝 Notas Importantes

1. **Ordem de Execução**: Sempre execute `make up` antes de outros comandos
2. **Inicialização**: Execute `make init` após `make up` na primeira vez
3. **Aguardar**: Dê tempo para os serviços iniciarem completamente (~30s)
4. **Limpeza**: Use `make clean` para reset completo do ambiente
5. **Profiles**: O Spark job usa profile `spark-streaming` no docker-compose

## 🔍 Verificar Status

```bash
# Status geral
make status

# Status detalhado
docker-compose ps
```

## 🎯 Workflows Recomendados

### Desenvolvimento Flink
```bash
make up
make init
# Editar código Java
make flink-build
make flink-cancel  # se já houver job rodando
make flink-job
make producer
make validate
```

### Desenvolvimento Spark
```bash
make up
make init
# Editar código Python
make spark-stop  # se já houver job rodando
make spark-job
make producer
make validate
```

### Demo/Apresentação
```bash
# Mostrar Flink
make test-flink

# Limpar e mostrar Spark
make clean
make test-spark
```

## 💡 Dicas

- Use `make help` para lembrar dos comandos
- Combine comandos: `make up && make init && make flink-job`
- Use `&` para rodar em background: `make producer &`
- Monitore logs em tempo real: `make logs`
- Acesse as UIs web para visualização gráfica
