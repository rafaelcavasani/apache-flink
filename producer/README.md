# Kafka Event Producer (Go)

Producer Golang para enviar eventos para Kafka baseado nos templates da pasta `events/`.

## Características

- ✅ Carrega automaticamente todos os templates JSON da pasta `events/`
- ✅ Gera IDs únicos (UUID) para cada evento
- ✅ Adiciona timestamp automático
- ✅ Mapeia templates para tópicos Kafka corretos
- ✅ Usa `id_recebivel` como key para garantir ordenação
- ✅ Configurável via flags CLI

## Instalação

```bash
cd producer
go mod download
```

## Uso

### Enviar 10 iterações (30 eventos total - 3 tipos)

```bash
go run main.go
```

### Enviar 100 iterações (300 eventos)

```bash
go run main.go -count 100
```

### Enviar com intervalo de 500ms

```bash
go run main.go -count 50 -interval 500ms
```

### Conectar em servidor Kafka diferente

```bash
go run main.go -bootstrap kafka:29092 -count 20
```

### Todas as flags disponíveis

```bash
go run main.go -h
```

## Flags CLI

| Flag | Padrão | Descrição |
|------|--------|-----------|
| `-bootstrap` | `localhost:9092` | Kafka bootstrap servers |
| `-events` | `../events` | Diretório com templates JSON |
| `-count` | `10` | Número de iterações (cada iteração envia 1 de cada tipo) |
| `-interval` | `1s` | Intervalo entre iterações |

## Mapeamento de Templates → Tópicos

| Template | Tópico Kafka |
|----------|--------------|
| `recebivel_agendado.json` | `recebiveis-eventos` |
| `recebivel_cancelado.json` | `cancelamentos` |
| `recebivel_negociado.json` | `negociacoes` |

## Estrutura dos Eventos Gerados

Cada evento recebe automaticamente:

```json
{
  "id_recebivel": "novo-uuid-gerado",
  "timestamp": "2025-12-23T14:30:00Z",
  "...demais campos do template..."
}
```

## Exemplos de Saída

```
Templates carregados: 3
  - recebivel_agendado.json → tópico: recebiveis-eventos
  - recebivel_cancelado.json → tópico: cancelamentos
  - recebivel_negociado.json → tópico: negociacoes

🚀 Iniciando envio de 10 eventos (intervalo: 1s)

✅ [1/30] Enviado: recebivel_agendado.json → recebiveis-eventos (id: a7f3c8e2-...)
✅ [2/30] Enviado: recebivel_cancelado.json → cancelamentos (id: b1e2f3a4-...)
✅ [3/30] Enviado: recebivel_negociado.json → negociacoes (id: d4e5f6a7-...)
...

✨ Total enviado: 30 eventos
```

## Build para Produção

```bash
# Compilar binário
go build -o kafka-producer

# Executar
./kafka-producer -bootstrap kafka:29092 -count 1000
```

## Dentro do Docker

```bash
# Copiar binário para container
docker cp kafka-producer flink-jobmanager:/tmp/

# Executar dentro do container
docker exec flink-jobmanager /tmp/kafka-producer -bootstrap kafka:29092 -count 100
```

## Testar Consumo dos Eventos

```bash
# Consumir tópico recebiveis-eventos
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic recebiveis-eventos \
  --from-beginning \
  --max-messages 5

# Consumir cancelamentos
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic cancelamentos \
  --from-beginning \
  --max-messages 5
```

## Verificar no Kafka UI

Acesse: http://localhost:8090

- Navegue até **Topics**
- Selecione `recebiveis-eventos`, `cancelamentos` ou `negociacoes`
- Visualize as mensagens enviadas
