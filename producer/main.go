package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/IBM/sarama"
	"github.com/google/uuid"
)

// EventTemplate representa a estrutura de um evento
type EventTemplate struct {
	Type     string
	Topic    string
	Template map[string]interface{}
}

// Config representa as configurações do producer
type Config struct {
	BootstrapServers string
	EventsDir        string
	Count            int
	Interval         time.Duration
}

// PaymentPool gerencia o pool de IDs de pagamento (thread-safe)
type PaymentPool struct {
	mu              sync.Mutex
	payments        []string
	receivablesLeft []int // quantos recebíveis ainda podem usar cada pagamento
	rng             *rand.Rand
}

// ReceivableValueTracker rastreia valores disponíveis por recebível
type ReceivableValueTracker struct {
	receivables map[string]*ReceivableState
	mu          sync.RWMutex
}

type ReceivableState struct {
	valorOriginal   float64
	valorDisponivel float64
	totalCancelado  float64
	totalNegociado  float64
}

// NewReceivableValueTracker cria um novo tracker
func NewReceivableValueTracker() *ReceivableValueTracker {
	return &ReceivableValueTracker{
		receivables: make(map[string]*ReceivableState),
	}
}

// InitReceivable inicializa um recebível com seu valor original
func (t *ReceivableValueTracker) InitReceivable(id string, valorOriginal float64) {
	t.mu.Lock()
	defer t.mu.Unlock()

	t.receivables[id] = &ReceivableState{
		valorOriginal:   valorOriginal,
		valorDisponivel: valorOriginal,
		totalCancelado:  0,
		totalNegociado:  0,
	}
}

// TryAllocateCancelado tenta alocar valor para cancelamento
// Retorna o valor alocado (pode ser menor que solicitado) e sucesso
func (t *ReceivableValueTracker) TryAllocateCancelado(id string, valorSolicitado float64) (float64, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()

	state, exists := t.receivables[id]
	if !exists {
		return 0, false
	}

	if state.valorDisponivel <= 0 {
		return 0, false
	}

	// Alocar o mínimo entre valor solicitado e disponível
	valorAlocado := valorSolicitado
	if valorAlocado > state.valorDisponivel {
		valorAlocado = state.valorDisponivel
	}

	state.valorDisponivel -= valorAlocado
	state.totalCancelado += valorAlocado

	return valorAlocado, true
}

// TryAllocateNegociado tenta alocar valor para negociação
// Retorna o valor alocado (pode ser menor que solicitado) e sucesso
func (t *ReceivableValueTracker) TryAllocateNegociado(id string, valorSolicitado float64) (float64, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()

	state, exists := t.receivables[id]
	if !exists {
		return 0, false
	}

	if state.valorDisponivel <= 0 {
		return 0, false
	}

	// Alocar o mínimo entre valor solicitado e disponível
	valorAlocado := valorSolicitado
	if valorAlocado > state.valorDisponivel {
		valorAlocado = state.valorDisponivel
	}

	state.valorDisponivel -= valorAlocado
	state.totalNegociado += valorAlocado

	return valorAlocado, true
}

// BaseReceivable armazena dados do recebível agendado para referência
type BaseReceivable struct {
	ID            string
	PaymentID     string
	ValorOriginal float64
	Event         map[string]interface{}
}

// EventJob representa um job de envio de evento
type EventJob struct {
	Topic string
	Event map[string]interface{}
	Type  string // "AGENDADO", "CANCELADO", "NEGOCIADO"
}

func newPaymentPool() *PaymentPool {
	return &PaymentPool{
		payments:        []string{},
		receivablesLeft: []int{},
		rng:             rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

// GetPaymentID retorna um id_pagamento, reutilizando ou criando novo (thread-safe)
func (p *PaymentPool) GetPaymentID() string {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Tentar reutilizar um pagamento existente que ainda tem espaço
	for i := 0; i < len(p.payments); i++ {
		if p.receivablesLeft[i] > 0 {
			p.receivablesLeft[i]--
			return p.payments[i]
		}
	}

	// Criar novo pagamento com capacidade aleatória de 1 a 6 recebíveis
	newPaymentID := uuid.New().String()
	capacity := p.rng.Intn(6) + 1 // 1 a 6

	p.payments = append(p.payments, newPaymentID)
	p.receivablesLeft = append(p.receivablesLeft, capacity-1) // -1 porque já estamos usando agora

	log.Printf("💳 Novo pagamento: %s (capacidade: %d recebíveis)\n", newPaymentID[:8], capacity)

	return newPaymentID
}

func main() {
	// Parse de argumentos
	config := parseFlags()

	// Configurar Kafka Producer (sarama)
	saramaConfig := sarama.NewConfig()
	saramaConfig.Producer.RequiredAcks = sarama.WaitForAll
	saramaConfig.Producer.Retry.Max = 5
	saramaConfig.Producer.Return.Successes = true
	saramaConfig.Producer.Return.Errors = true

	producer, err := sarama.NewSyncProducer([]string{config.BootstrapServers}, saramaConfig)
	if err != nil {
		log.Fatalf("Erro ao criar producer: %v", err)
	}
	defer producer.Close()

	// Carregar templates de eventos
	allTemplates, err := loadEventTemplates(config.EventsDir)
	if err != nil {
		log.Fatalf("Erro ao carregar templates: %v", err)
	}

	// Separar template base (agendado) dos derivados (cancelado, negociado)
	var baseTemplate EventTemplate
	var derivedTemplates []EventTemplate

	for _, t := range allTemplates {
		if t.Type == "recebivel_agendado.json" {
			baseTemplate = t
		} else {
			derivedTemplates = append(derivedTemplates, t)
		}
	}

	log.Printf("Templates carregados: %d\n", len(allTemplates))
	log.Printf("  - Base: %s → tópico: %s\n", baseTemplate.Type, baseTemplate.Topic)
	for _, t := range derivedTemplates {
		log.Printf("  - Derivado: %s → tópico: %s (30%% probabilidade)\n", t.Type, t.Topic)
	}

	// Criar pool de pagamentos, tracker e RNG
	paymentPool := newPaymentPool()
	valueTracker := NewReceivableValueTracker()
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))

	// Channels e sincronização
	const numWorkers = 20
	jobsChan := make(chan EventJob, 200)
	var wg sync.WaitGroup
	var eventCount int64

	// Iniciar workers
	for w := 1; w <= numWorkers; w++ {
		wg.Add(1)
		go worker(w, producer, jobsChan, &wg, &eventCount)
	}

	// Enviar eventos
	log.Printf("\n🚀 Iniciando envio de %d recebíveis agendados (workers: %d, intervalo: %v)\n", config.Count, numWorkers, config.Interval)
	log.Printf("📊 Eventos derivados: 30%% probabilidade (com restrição: cancelado+negociado ≤ valor_original)\n\n")

	for i := 0; i < config.Count; i++ {
		// 1. SEMPRE produzir recebivel_agendado (base da agregação)
		baseReceivable := generateBaseReceivable(baseTemplate, paymentPool)

		// Inicializar tracker com valor original
		valueTracker.InitReceivable(baseReceivable.ID, baseReceivable.ValorOriginal)

		jobsChan <- EventJob{
			Topic: baseTemplate.Topic,
			Event: baseReceivable.Event,
			Type:  "AGENDADO",
		}

		// 2. Produzir eventos derivados com 30% de probabilidade
		for _, derivedTemplate := range derivedTemplates {
			if rng.Float64() < 0.30 { // 30% de chance
				derivedEvent, valor := generateDerivedEvent(derivedTemplate, baseReceivable, valueTracker, rng)

				// Só enviar se conseguiu alocar valor
				if valor > 0 {
					eventType := "CANCELADO"
					if derivedTemplate.Type == "recebivel_negociado.json" {
						eventType = "NEGOCIADO"
					}

					jobsChan <- EventJob{
						Topic: derivedTemplate.Topic,
						Event: derivedEvent,
						Type:  eventType,
					}
				}
			}
		}

		if i < config.Count-1 {
			time.Sleep(config.Interval)
		}
	}

	// Fechar channel e aguardar workers
	close(jobsChan)
	wg.Wait()

	finalCount := atomic.LoadInt64(&eventCount)
	log.Printf("\n✨ Total enviado: %d eventos (processados por %d workers)\n", finalCount, numWorkers)
}

func parseFlags() Config {
	bootstrapServers := flag.String("bootstrap", "localhost:9092", "Kafka bootstrap servers")
	eventsDir := flag.String("events", "../events", "Diretório com templates de eventos")
	count := flag.Int("count", 10, "Número de iterações (cada iteração envia 1 de cada tipo)")
	interval := flag.Duration("interval", 10*time.Millisecond, "Intervalo entre iterações")

	flag.Parse()

	return Config{
		BootstrapServers: *bootstrapServers,
		EventsDir:        *eventsDir,
		Count:            *count,
		Interval:         *interval,
	}
}

func loadEventTemplates(dir string) ([]EventTemplate, error) {
	files, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("erro ao ler diretório: %w", err)
	}

	templates := []EventTemplate{}

	for _, file := range files {
		if file.IsDir() || filepath.Ext(file.Name()) != ".json" {
			continue
		}

		filePath := filepath.Join(dir, file.Name())
		data, err := os.ReadFile(filePath)
		if err != nil {
			log.Printf("⚠️  Ignorando arquivo %s: %v\n", file.Name(), err)
			continue
		}

		var template map[string]interface{}
		if err := json.Unmarshal(data, &template); err != nil {
			log.Printf("⚠️  Erro ao parsear %s: %v\n", file.Name(), err)
			continue
		}

		// Determinar tópico com base no nome do arquivo
		topic := determineTopicFromFilename(file.Name())

		templates = append(templates, EventTemplate{
			Type:     file.Name(),
			Topic:    topic,
			Template: template,
		})
	}

	return templates, nil
}

func determineTopicFromFilename(filename string) string {
	// Mapear nomes de arquivo para tópicos Kafka
	topicMap := map[string]string{
		"recebivel_agendado.json":  "recebiveis-agendados",
		"recebivel_cancelado.json": "recebiveis-cancelados",
		"recebivel_negociado.json": "recebiveis-negociados",
	}

	if topic, ok := topicMap[filename]; ok {
		return topic
	}

	// Fallback: usar nome do arquivo sem extensão
	return filename[:len(filename)-5]
}

// generateBaseReceivable cria o evento base (recebivel_agendado)
func generateBaseReceivable(template EventTemplate, paymentPool *PaymentPool) struct {
	ID            string
	PaymentID     string
	ValorOriginal float64
	Event         map[string]interface{}
} {
	event := make(map[string]interface{})

	// Copiar template
	for key, value := range template.Template {
		event[key] = value
	}

	// Gerar IDs e timestamp
	id := uuid.New().String()
	paymentID := paymentPool.GetPaymentID()

	event["id_recebivel"] = id
	event["id_pagamento"] = paymentID
	event["timestamp"] = time.Now().UTC().Format(time.RFC3339)
	event["tipo_evento"] = "agendado"

	// Extrair valor_original
	valorOriginal := event["valor_original"].(float64)

	return struct {
		ID            string
		PaymentID     string
		ValorOriginal float64
		Event         map[string]interface{}
	}{
		ID:            id,
		PaymentID:     paymentID,
		ValorOriginal: valorOriginal,
		Event:         event,
	}
}

// generateDerivedEvent cria eventos derivados (cancelado/negociado)
// Retorna o evento e o valor alocado (0 se não conseguiu alocar)
func generateDerivedEvent(template EventTemplate, base struct {
	ID            string
	PaymentID     string
	ValorOriginal float64
	Event         map[string]interface{}
}, tracker *ReceivableValueTracker, rng *rand.Rand) (map[string]interface{}, float64) {
	event := make(map[string]interface{})

	// Copiar template
	for key, value := range template.Template {
		event[key] = value
	}

	// Usar mesmo id_recebivel e id_pagamento do evento base
	event["id_recebivel"] = base.ID
	event["id_pagamento"] = base.PaymentID
	event["timestamp"] = time.Now().UTC().Format(time.RFC3339)

	// Definir tipo_evento baseado no template
	if template.Type == "recebivel_cancelado.json" {
		event["tipo_evento"] = "cancelado"
	} else if template.Type == "recebivel_negociado.json" {
		event["tipo_evento"] = "negociado"
	}

	// Gerar IDs únicos específicos
	if _, exists := event["id_cancelamento"]; exists {
		event["id_cancelamento"] = uuid.New().String()
	}
	if _, exists := event["id_negociacao"]; exists {
		event["id_negociacao"] = uuid.New().String()
	}

	// Calcular valor solicitado: 10% igual ao original, 90% parcial (10%-90% do original)
	var valorSolicitado float64
	if rng.Float64() < 0.10 { // 10% de chance de ser valor total
		valorSolicitado = base.ValorOriginal
	} else { // 90% de chance de ser valor parcial
		// Entre 10% e 90% do valor original
		percentage := 0.10 + rng.Float64()*0.80 // 0.10 a 0.90
		valorSolicitado = base.ValorOriginal * percentage
	}

	// Tentar alocar valor respeitando restrição (cancelado+negociado ≤ valor_original)
	var valorAlocado float64
	var success bool

	if template.Type == "recebivel_cancelado.json" {
		valorAlocado, success = tracker.TryAllocateCancelado(base.ID, valorSolicitado)
		if success && valorAlocado > 0 {
			event["valor_cancelado"] = valorAlocado
		} else {
			return nil, 0 // Não conseguiu alocar
		}
	} else if template.Type == "recebivel_negociado.json" {
		valorAlocado, success = tracker.TryAllocateNegociado(base.ID, valorSolicitado)
		if success && valorAlocado > 0 {
			event["valor_negociado"] = valorAlocado
		} else {
			return nil, 0 // Não conseguiu alocar
		}
	}

	return event, valorAlocado
}

func sendEvent(producer sarama.SyncProducer, topic string, event map[string]interface{}) error {
	eventJSON, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("erro ao serializar evento: %w", err)
	}

	// Usar id_recebivel como key para garantir ordem de eventos do mesmo recebível
	key := event["id_recebivel"].(string)

	msg := &sarama.ProducerMessage{
		Topic: topic,
		Key:   sarama.StringEncoder(key),
		Value: sarama.ByteEncoder(eventJSON),
	}

	_, _, err = producer.SendMessage(msg)
	return err
}

// worker processa jobs de envio de eventos em paralelo
func worker(id int, producer sarama.SyncProducer, jobs <-chan EventJob, wg *sync.WaitGroup, eventCount *int64) {
	defer wg.Done()

	for job := range jobs {
		err := sendEvent(producer, job.Topic, job.Event)
		if err != nil {
			log.Printf("❌ [Worker %d] Erro ao enviar %s: %v\n", id, job.Type, err)
			continue
		}

		count := atomic.AddInt64(eventCount, 1)

		if job.Type == "AGENDADO" {
			log.Printf("✅ [%d] %s: id=%s, pagamento=%s, valor=%.2f\n",
				count,
				job.Type,
				job.Event["id_recebivel"].(string)[:8],
				job.Event["id_pagamento"].(string)[:8],
				job.Event["valor_original"].(float64))
		} else {
			valorKey := "valor_cancelado"
			if job.Type == "NEGOCIADO" {
				valorKey = "valor_negociado"
			}
			log.Printf("   └─ [Worker %d] %s: valor=%.2f\n",
				id,
				job.Type,
				job.Event[valorKey].(float64))
		}
	}
}
