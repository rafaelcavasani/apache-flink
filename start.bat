@echo off
echo =============================================
echo  Inicializando Pipeline de Agregacao
echo =============================================
echo.

echo [1/3] Subindo containers...
docker-compose up -d

echo.
echo [2/3] Aguardando servicos iniciarem (30 segundos)...
timeout /t 30 /nobreak > nul

echo.
echo [3/3] Inicializando Kafka e DynamoDB...
echo.

echo --- Criando topicos no Kafka ---
bash init-kafka.sh

echo.
echo --- Criando tabelas no DynamoDB ---
bash init-dynamodb.sh

echo.
echo =============================================
echo  Pipeline inicializada com sucesso!
echo =============================================
echo.
echo Interfaces disponiveis:
echo   - Flink Dashboard:   http://localhost:8081
echo   - Kafka UI:          http://localhost:8090
echo   - Elasticsearch:     http://localhost:9200
echo   - DynamoDB Admin:    http://localhost:8001
echo.
pause
