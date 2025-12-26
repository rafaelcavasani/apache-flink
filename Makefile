.PHONY: help up down logs clean flink-job spark-job spark-stop kafka-topics init-db init-es validate producer test-flink test-spark

# Cores para output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RESET := \033[0m

help: ## Mostra esta mensagem de ajuda
	@echo "$(BLUE)=====================================================$(RESET)"
	@echo "$(GREEN)  Receivable Aggregator - Comandos Disponíveis$(RESET)"
	@echo "$(BLUE)=====================================================$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)=====================================================$(RESET)"

# ==========================================
# Gerenciamento de Containers
# ==========================================

services: ## Inicia apenas infraestrutura (Kafka, ES, DynamoDB) sem jobs
	@echo "$(GREEN)🚀 Iniciando serviços de infraestrutura...$(RESET)"
	docker-compose up -d zookeeper kafka kafka-ui elasticsearch dynamodb dynamodb-admin
	@echo "$(GREEN)✅ Infraestrutura iniciada!$(RESET)"
	@echo ""
	@echo "$(BLUE)Serviços disponíveis:$(RESET)"
	@echo "  - Kafka UI:        http://localhost:8090"
	@echo "  - Elasticsearch:   http://localhost:9200"
	@echo "  - DynamoDB Admin:  http://localhost:8001"
	@echo ""
	@echo "$(YELLOW)Para iniciar jobs:$(RESET)"
	@echo "  - Flink:  make up-flink  ou  make flink-job"
	@echo "  - Spark:  make up-spark  ou  make spark-job"

up: ## Inicia todos os serviços (Kafka, ES, DynamoDB, Flink, Spark)
	@echo "$(GREEN)🚀 Iniciando todos os serviços...$(RESET)"
	docker-compose up -d
	@echo "$(GREEN)✅ Serviços iniciados!$(RESET)"
	@echo ""
	@echo "$(BLUE)Serviços disponíveis:$(RESET)"
	@echo "  - Kafka UI:        http://localhost:8090"
	@echo "  - Elasticsearch:   http://localhost:9200"
	@echo "  - DynamoDB Admin:  http://localhost:8001"
	@echo "  - Flink UI:        http://localhost:8081"
	@echo "  - Spark UI:        http://localhost:8082"

up-flink: ## Inicia apenas cluster Flink (JobManager + TaskManagers)
	@echo "$(BLUE)🚀 Iniciando cluster Flink...$(RESET)"
	docker-compose up -d jobmanager taskmanager
	@echo "$(GREEN)✅ Flink iniciado!$(RESET)"
	@echo "$(BLUE)Flink UI: http://localhost:8081$(RESET)"

up-spark: ## Inicia apenas cluster Spark (Master + Workers)
	@echo "$(BLUE)🚀 Iniciando cluster Spark...$(RESET)"
	docker-compose up -d spark-master spark-worker
	@echo "$(GREEN)✅ Spark iniciado!$(RESET)"
	@echo "$(BLUE)Spark UI: http://localhost:8082$(RESET)"

down: ## Para e remove todos os containers
	@echo "$(YELLOW)⏹️  Parando todos os serviços...$(RESET)"
	docker-compose down
	@echo "$(GREEN)✅ Serviços parados!$(RESET)"

logs: ## Mostra logs de todos os serviços
	docker-compose logs -f

clean: ## Remove volumes e faz limpeza completa
	@echo "$(RED)🗑️  Removendo todos os containers e volumes...$(RESET)"
	docker-compose down -v
	@echo "$(GREEN)✅ Limpeza concluída!$(RESET)"

# ==========================================
# Flink Jobs
# ==========================================

flink-build: ## Compila o job Flink
	@echo "$(BLUE)🔨 Compilando job Flink...$(RESET)"
	cd flinkjob && mvn clean package -DskipTests
	@echo "$(GREEN)✅ Job Flink compilado!$(RESET)"

flink-job: flink-build ## Submete o job Flink para execução
	@echo "$(BLUE)🚀 Submetendo job Flink...$(RESET)"
	@if [ ! -f flinkjob/target/receivable-aggregator-1.0-SNAPSHOT.jar ]; then \
		echo "$(RED)❌ JAR não encontrado. Execute 'make flink-build' primeiro.$(RESET)"; \
		exit 1; \
	fi
	docker exec -it flink-jobmanager flink run \
		-d \
		/opt/flink/usrlib/receivable-aggregator-1.0-SNAPSHOT.jar
	@echo "$(GREEN)✅ Job Flink submetido!$(RESET)"
	@echo "$(BLUE)Acesse: http://localhost:8081$(RESET)"

flink-cancel: ## Cancela todos os jobs Flink em execução
	@echo "$(YELLOW)⏹️  Cancelando jobs Flink...$(RESET)"
	@JOB_IDS=$$(docker exec flink-jobmanager flink list -r 2>/dev/null | grep -oP '(?<=: )[a-f0-9]{32}' || true); \
	if [ -z "$$JOB_IDS" ]; then \
		echo "$(YELLOW)⚠️  Nenhum job em execução.$(RESET)"; \
	else \
		for JOB_ID in $$JOB_IDS; do \
			echo "$(YELLOW)Cancelando job: $$JOB_ID$(RESET)"; \
			docker exec flink-jobmanager flink cancel $$JOB_ID; \
		done; \
		echo "$(GREEN)✅ Jobs cancelados!$(RESET)"; \
	fi

flink-list: ## Lista todos os jobs Flink
	@echo "$(BLUE)📋 Jobs Flink:$(RESET)"
	@docker exec flink-jobmanager flink list -a || echo "$(YELLOW)⚠️  Nenhum job encontrado.$(RESET)"

# ==========================================
# Spark Jobs
# ==========================================

spark-job: ## Inicia o job Spark em background (com workers e checkpoints limpos)
	@echo "$(BLUE)🚀 Iniciando cluster Spark...$(RESET)"
	@echo "$(YELLOW)🧹 Limpando checkpoints antigos...$(RESET)"
	@docker exec spark-master rm -rf /tmp/spark-checkpoints/* 2>nul || echo Checkpoints limpos
	@echo "$(BLUE)⚙️  Iniciando Spark Master + Workers...$(RESET)"
	docker-compose up -d spark-master
	docker-compose up -d --scale spark-worker=2 spark-worker
	@echo "$(BLUE)⏳ Aguardando workers conectarem (5 segundos)...$(RESET)"
	@timeout /t 5 /nobreak >nul 2>nul || sleep 5
	@echo "$(BLUE)🚀 Iniciando job Spark...$(RESET)"
	docker-compose --profile spark-streaming up -d spark-job
	@echo "$(GREEN)✅ Job Spark iniciado com sucesso!$(RESET)"
	@echo ""
	@echo "$(BLUE)Serviços disponíveis:$(RESET)"
	@echo "  - Spark Master UI: http://localhost:8082"
	@echo "  - Spark Job Logs:  docker-compose logs -f spark-job"
	@echo ""
	@echo "$(YELLOW)Aguarde ~30 segundos para o primeiro batch processar$(RESET)"

spark-stop: ## Para o job Spark
	@echo "$(YELLOW)⏹️  Parando job Spark...$(RESET)"
	docker-compose stop spark-job
	docker-compose rm -f spark-job
	@echo "$(GREEN)✅ Job Spark parado!$(RESET)"

spark-logs: ## Mostra logs do job Spark
	docker-compose logs -f spark-job

spark-local: ## Executa o job Spark localmente (fora do Docker)
	@echo "$(BLUE)🚀 Executando job Spark localmente...$(RESET)"
	cd sparkjob && python run.py

# ==========================================
# Inicialização de Dados
# ==========================================

init-db: ## Cria a tabela no DynamoDB
	@echo "$(BLUE)🗄️  Criando tabela DynamoDB...$(RESET)"
	cd scripts && pwsh -File init-dynamodb.ps1
	@echo "$(GREEN)✅ Tabela DynamoDB criada!$(RESET)"

init-es: ## Cria o índice no Elasticsearch
	@echo "$(BLUE)🔍 Criando índice Elasticsearch...$(RESET)"
	cd scripts && pwsh -File init-elasticsearch.ps1
	@echo "$(GREEN)✅ Índice Elasticsearch criado!$(RESET)"

init-kafka: ## Cria os tópicos no Kafka
	@echo "$(BLUE)📨 Criando tópicos Kafka...$(RESET)"
	cd scripts && pwsh -File init-kafka.ps1
	@echo "$(GREEN)✅ Tópicos Kafka criados!$(RESET)"

init: init-kafka init-db init-es ## Inicializa todos os recursos (Kafka, DynamoDB, Elasticsearch)
	@echo ""
	@echo "$(GREEN)🎉 Todos os recursos inicializados!$(RESET)"

# ==========================================
# Testes e Validação
# ==========================================

producer: ## Executa o producer Go para gerar eventos de teste
	@echo "$(BLUE)📤 Executando producer (100 eventos)...$(RESET)"
	cd producer && go run main.go -count 100 -interval 10ms
	@echo "$(GREEN)✅ Eventos enviados!$(RESET)"

producer-continuous: ## Executa o producer continuamente (2 minutos)
	@echo "$(BLUE)📤 Executando producer continuamente (2 minutos)...$(RESET)"
	cd producer && go run main.go -count 1000 -interval 5ms
	@echo "$(GREEN)✅ Producer finalizado!$(RESET)"

validate: ## Valida consistência entre DynamoDB e Elasticsearch
	@echo "$(BLUE)🔍 Validando consistência de dados...$(RESET)"
	cd scripts && pwsh -File validate-data-consistency.ps1

test-flink: init flink-job producer validate ## Pipeline completo de teste com Flink
	@echo ""
	@echo "$(GREEN)🎉 Teste Flink completo!$(RESET)"

test-spark: init spark-job producer validate spark-stop ## Pipeline completo de teste com Spark
	@echo ""
	@echo "$(GREEN)🎉 Teste Spark completo!$(RESET)"

# ==========================================
# Utilitários
# ==========================================

kafka-topics: ## Lista todos os tópicos Kafka
	@echo "$(BLUE)📋 Tópicos Kafka:$(RESET)"
	docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list

es-count: ## Conta documentos no Elasticsearch
	@echo "$(BLUE)📊 Contagem Elasticsearch:$(RESET)"
	@curl -s http://localhost:9200/ciclo_vida_recebiveis/_count | jq

dynamodb-count: ## Conta itens no DynamoDB
	@echo "$(BLUE)📊 Contagem DynamoDB:$(RESET)"
	@aws dynamodb scan --table-name Recebiveis --select COUNT --endpoint-url http://localhost:8000 --region us-east-1 | jq '.Count'

status: ## Mostra status de todos os serviços
	@echo "$(BLUE)=====================================================$(RESET)"
	@echo "$(GREEN)  Status dos Serviços$(RESET)"
	@echo "$(BLUE)=====================================================$(RESET)"
	@docker-compose ps
	@echo ""
	@echo "$(BLUE)Elasticsearch:$(RESET)"
	@curl -s http://localhost:9200/_cluster/health | jq -r '"  Status: \(.status) | Nodes: \(.number_of_nodes)"' 2>/dev/null || echo "  $(RED)Offline$(RESET)"
	@echo ""
	@echo "$(BLUE)Kafka Topics:$(RESET)"
	@docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | sed 's/^/  /' || echo "  $(RED)Offline$(RESET)"

# ==========================================
# Desenvolvimento
# ==========================================

shell-flink: ## Abre shell no Flink JobManager
	docker exec -it flink-jobmanager bash

shell-spark: ## Abre shell no Spark Master
	docker exec -it spark-master bash

shell-kafka: ## Abre shell no Kafka
	docker exec -it kafka bash

restart: down up ## Reinicia todos os serviços

# Default target
.DEFAULT_GOAL := help
