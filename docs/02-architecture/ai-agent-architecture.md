# Arquitetura da Bea (plugin `ai_agent`)

> Documento de arquitetura técnica. A **fonte de verdade é o código** em
> `plugins/ai_agent/` — este texto descreve o que está implementado hoje
> (revisão 2026-05-30). Quando código e documento divergirem, o código vence;
> atualize o documento.

A **Bea** (assistente "Beatriz") é a recepcionista de IA single-agent da Klivy.
Ela vive em dois pipelines distintos:

- **Pipeline A** — responde **pacientes** no WhatsApp (via Chatwoot inbox).
- **Pipeline B** — responde a **equipe interna** quando alguém menciona
  `@beatriz` / `@bea` no Chat Interno.

Os dois pipelines compartilham os mesmos providers de LLM, o catálogo de tools
(em variantes), `UsageCounter` e configuração 3-camadas, mas têm orquestradores,
jobs e conjuntos de tools separados.

---

## 1. Pipeline A — Paciente no WhatsApp

### 1.1 Visão geral do fluxo

```
WhatsApp → Chatwoot Message (incoming)
        │
        │ Message#after_create_commit  (callback DIRETO, NÃO Wisper)
        ▼
AiAgent::EventListeners::MessageListener#message_created
        │  filtros baratos → primeiro→mais caro
        │  rate limit (RateLimiter)
        ▼
AiAgent::ChatResponseJob  (Sidekiq, retry: 0)
        │  coalescing + idempotência (Trace) + áudio/imagem
        ▼
AiAgent::ChatService#respond  (orquestrador de 1 turno)
        │  guards → emergency → captain quota → escalation
        │  → state machine determinística → LLM + tools
        │  → guardrail → sentinel (opt-in) → Trace
        ▼
post_reply → Chatwoot outgoing message (AgentBot "Bea")
```

### 1.2 Trigger: `Message#after_create_commit` (callback direto, não Wisper)

O ponto de entrada **não** é um subscriber Wisper. O engine
(`lib/ai_agent/engine.rb`, dentro de `config.to_prepare`) faz `Message.class_eval`
e instala `after_create_commit :trigger_ai_agent_listener`. Esse callback monta
um `Struct` de evento e chama `MessageListener.instance.message_created` na
**mesma transação de commit** em que a mensagem foi persistida.

**Por que não Wisper:** as subscrições Wisper evaporavam em dev reloads
(o `event_handlers.rb` do Chatwoot refaz `dispatcher.load_listeners` em todo
`to_prepare`), fazendo a Bea perder mensagens de forma intermitente. O callback
direto não tem dependência de Redis/Sidekiq no caminho de dispatch — só o **job**
em si vai pro Sidekiq, com `rescue` ao redor do enqueue.

> Há também `AiAgent::DispatcherExtension` que adiciona o `MessageListener` à
> lista do `AsyncDispatcher` — mas o caminho real e confiável é o callback direto.

### 1.3 `MessageListener` — filtros e debounce

`should_handle?` aplica filtros do mais barato ao mais caro (curto-circuita cedo):

1. `message.incoming?` (do contato, não do agente)
2. sender é um `Contact` real (`sender_type == 'Contact'` + `sender_id` presente)
   — evita loop bot-contra-bot
3. não é `private?`
4. não foi enviada via API (`content_attributes['sent_via_api'] != true`)
5. tem texto **ou** attachment processável (`audio`/`image`/`video`/`file`)
6. `account.ai_agent_setting&.enabled`
7. **a inbox tem a Beatriz vinculada** (`CaptainInbox` para `Captain::Assistant`
   "Beatriz")
8. `ConversationState` da conversa não está `escalated`
9. conversa não tem `assignee_id` (humano já assumiu)

Passando os filtros, aplica `AiAgent::RateLimiter` (conta+conversa) e enfileira
`ChatResponseJob` com `wait: DEBOUNCE_SECONDS (3s)` e `account_id:` explícito
(defesa cross-tenant, MT-5).

O **debounce de 3s** absorve o burst típico do WhatsApp (paciente fragmenta em
mensagens curtas). Se chega outra incoming nesse intervalo, o job da primeira
detecta a mais nova e pula (coalescing — ver abaixo).

### 1.4 `ChatResponseJob` — coalescing, idempotência, multimodal

`sidekiq_options retry: 0` — retry automático do Sidekiq desligado: a `ChatService`
já tem retry interno para erros transientes de provider, e re-rodar o job inteiro
após sucesso parcial postaria resposta duplicada ao paciente.

Ordem do `perform(message_id, attempt:, account_id:)`:

1. **Validação cross-tenant** — `message.account_id == account_id`.
2. **Coalescing** — se existe uma incoming **mais nova** na mesma conversa, pula
   (a mais nova responde por todas).
3. **Idempotência forte** — se já existe `Trace` bem-sucedido (`error_message: nil`)
   para essa `message_id`, pula. Garantido por índice único parcial; em race, um
   job cria o `Trace` e o outro recebe `RecordNotUnique` → `DuplicateTurnError`.
4. **Typing indicator** — ActionCable (dashboard) + presença WhatsApp via bridge
   Baileys (`/sessions/:inbox_id/presence`), best-effort.
5. **Handoff visual** — se a mensagem é imagem/vídeo, classifica via
   `Multimodal::ImageHandler` e escala humano (CFM proíbe a Bea interpretar
   conteúdo médico de imagem). Não chama LLM.
6. **Transcrição de áudio** — PTT do WhatsApp transcrito por
   `Multimodal::AudioTranscriber` (Whisper); a transcrição vira `message.content`.
   Se o blob ainda não chegou ao storage (`:file_not_ready`), reenfileira com
   delay (até `MAX_BLOB_RETRY = 3`, `BLOB_RETRY_DELAY = 5s`); senão, fallback
   pedindo texto.
7. **Histórico** — `Memory::CrossConversationHistory` (janela 24h, atravessa
   conversas do mesmo Contact) ou fallback à conversa atual.
8. Chama `ChatService#respond` e posta a resposta como outgoing do AgentBot.
9. `promote_to_open` — toda resposta promove a conversa de `pending` → `open`
   (`bot_handoff!`), senão fica invisível na aba "Abertas".
10. `handle_handoff` se `result.handoff`.

### 1.5 `ChatService#respond` — ordem do turno

A ordem dos guards é **deliberada** (segurança antes de custo, determinismo antes
de LLM):

1. **Guards de entrada** — `user_message` não vazio; `resolver.enabled?`
   (senão `BeaDisabledError`); `resolver.over_monthly_cost_cap?` (senão
   `BudgetExceededError`). Inicializa `::Llm::Config`.
2. **Carrega contexto** — `ConversationState`, `PatientMemory`, `Context` struct.
3. **Tracking + sentiment** — `track_message_repetition` (idempotente por
   `message_id`) e `apply_sentiment` (só se `CAPTAIN_BEA_SENTIMENT_ENABLED`).
4. **Emergência determinística** — `Emergency::Detector` classifica por keyword
   PT-BR **antes do LLM**. Se disparar → `emergency_short_circuit`: template fixo
   (SAMU 192 / CVV 188), escala humano, notifica equipe, `< 100ms`, sem LLM.
5. **Detectores paralelos (não interrompem)** — `OffensiveTone` e `RefundRequest`
   notificam equipe interna; a Bea continua respondendo normalmente.
6. **Opt-out de recall** — se o paciente respondeu "NÃO"/"PARE"/"STOP" dentro de
   7 dias de um recall proativo, marca preferência e responde determinístico.
7. **Captain quota** — `captain_quota_exhausted?` → `captain_quota_handoff`
   (compartilha a cota `captain_responses` do plano).
8. **Escalation rules** — `Humanization::EscalationRules` avalia handoff
   **antes do LLM** (pedido explícito de humano, sinal clínico urgente, sentimento
   negativo persistente, loop de tool, mensagem repetida). Se escalar →
   `early_handoff`.
9. **State machine determinística** — se o paciente respondeu confirmação curta
   ("sim", "ok") e há `pending_offer`, executa book/reschedule **sem LLM**
   (`handle_deterministic_confirmation`). Idem para aceite com horário específico
   que casa com `pending_offer.alternatives` (`offer_match_for`).
10. **Context block** — `ContextBuilder` injeta datetime, status aberto/fechado,
    datas de referência ("amanhã" → DD/MM), hints de paciente. Vai como **prefixo
    da mensagem do usuário**, nunca no system prompt (preserva cache-hit). Inclui
    âncoras anti-drift de serviço ativo e de paciente-alvo (família WhatsApp).
11. **LLM + tools** — `with_provider_fallback` constrói o `RubyLLM.chat`,
    `PromptBuilder.system_instructions`, registra as tools habilitadas
    (`ToolRegistry.lookup(resolver.enabled_tools)`) com wrapper de captura de
    estado, e envia histórico via `HistoryFormatter`.
12. **Guardrail** — `Guardrail::Validator` sanitiza a saída (diagnóstico,
    prescrição, garantia). Se inseguro, substitui por template e escala.
13. **Detectores pós-resposta** — `EvasiveResponse` (3 evasivas em 60min →
    alerta de lacuna na KB).
14. **Sentinel (opt-in)** — `run_sentinel` registra verdict no `Trace`, não
    regenera (ver §6).
15. **Persistência** — `record_usage` (`UsageCounter` + cota Captain) e
    `persist_trace` (custo, latência, tokens, tools, sentimento, escalation,
    violações).

#### 1.5.1 Wrapper de tools (state capture + defesas)

Cada tool instanciada tem seu `execute` sobrescrito por
`wrap_tool_for_state_capture` para, sem editar cada tool:

- **Anti-anchor de serviço** — se há serviço ativo no fluxo e o LLM passa outro
  `service_id` sem o paciente ter pedido, sobrescreve (a menos que o paciente
  tenha mencionado o serviço novo explicitamente).
- **Auto-inject `patient_id`** em `book_appointment` quando há terceiro ativo
  (família WhatsApp) e o LLM esqueceu; se o Contact tem >1 Patient ativo, recusa
  pedindo clarificação.
- **Critique 1-step** (`Humanization::Critique`) antes de `book`/`reschedule` —
  rejeita data passada, fora do horário, profissional que não faz o serviço, etc.,
  retornando erro estruturado ao LLM sem custo extra.
- Atualiza o state machine via `StateMachineUpdater.record`.

### 1.6 Eventos/callbacks injetados (`to_prepare`)

Além do trigger de `Message`, o engine injeta callbacks em outros modelos do core
(idempotentes via `unless method_defined?`):

| Modelo | Callback | Efeito |
|---|---|---|
| `Account` | `after_create_commit` | cria `Captain::Assistant` "Beatriz" default + seed de 10 templates de notificação interna (desativados) |
| `Captain::Assistant` | `before_destroy`/`before_update`/`after_save` | protege "Beatriz" de delete/rename; espelha toggle on/off em `AccountSetting.enabled` |
| `Captain::Conversation::ResponseBuilderJob` | `prepend SkipBeatrizLegacyResponse` | evita resposta dupla (legacy Captain + Bea) |
| `AgendaEvent` | `after_commit on: [:create,:update]` | notifica Chat Interno em `pending_confirmation` (source `ai_agent`), `cancelled`, `no_show` |
| `Conversation` | `after_update_commit` | quando resolvida, volta `ConversationState` para `active` (senão a Bea fica silenciada para sempre após um handoff) |
| `BookAppointmentTool` | `prepend BookAppointmentToolPrepend` | notifica equipe quando booking falha de forma não-trivial |

---

## 2. Pipeline B — Staff `@beatriz` no Chat Interno

Pipeline **propositalmente enxuto**: sem state machine, sem patient memory, sem
follow-ups, sem sentinel. É conversa profissional-com-profissional.

```
InternalChat::Message (staff menciona @beatriz)
        │  InternalChat::MessageDispatcher (após persistir + registrar mentions)
        ▼
InternalChat::AiAgentMentionListener.call(message:, ai_agent_ids:)
        │  loop guard (ignora sender IA) + BeaResolver + bea ∈ menções
        ▼
AiAgent::InternalChat::RespondJob (Sidekiq async)
        ▼
AiAgent::InternalChat::Responder#respond
        │  carrega contexto (histórico N=10 + reply) → SystemPrompt
        │  → LLM com Toolset privilegiado (checa RBAC do invoking_user)
        │  → posta resposta como Bea (in_reply_to)
        ▼
InternalChat::MessageDispatcher (Bea responde na sala)
```

**Filtros do `Responder`:**
- não responde a mensagem de sistema;
- **defesa cross-tenant** — se enfileirado com `account_id`, valida que a mensagem
  pertence a essa conta;
- `BeaResolver.for_account` precisa existir;
- loop guard — não responde a `sender_ai_agent_id` presente;
- confirma a menção pela tabela `internal_chat_mentions` (fonte de verdade);
- `InternalChat::RateLimiter` (30 respostas/sala/dia — ver §7).

**RBAC do `invoking_user`:** o `Responder` propaga `message.sender` (o `User` que
mencionou a Bea) para `Toolset.tools_for(account, invoking_user:)`. Os tools
privilegiados checam a permissão granular Klivy desse usuário **antes** de
executar (SEC-12). Sem isso, um recepcionista sem `agenda:cancel_event`
conseguiria cancelar pela Bea o que não consegue pela UI. Se `sender` é `nil`
(Bea respondendo a outra IA), os tools tratam como "sem invocador humano" e
bloqueiam ações privilegiadas por padrão.

O modelo é resolvido por `model_for_account` (mesmas flags de provider/modelo),
com defaults legados próprios (`gemini-2.5-flash` / `gpt-4o-mini`). **Não há
fallback/circuit breaker** neste pipeline (diferente do A).

---

## 3. Catálogo de Tools

`AiAgent::ToolRegistry::BUILTIN` mapeia `key → classe`. No Pipeline A o
`ConfigResolver#enabled_tools` interseca o whitelist da conta com as
`ToolDefinition.enabled` globais. O Pipeline B usa um conjunto fixo
(`InternalChat::Toolset::ENABLED_TOOL_CLASSES`).

Todos os tools herdam de `AiAgent::Tools::BaseTool` (subclasse de `RubyLLM::Tool`),
recebem um `Context` (account, contact_id, state, memory, invoking_user) e expõem
um nome snake_case limpo (ex.: `book_appointment`).

### 3.1 Tools do Pipeline A (built-in, LLM-called)

| key | O que faz | RBAC / gates |
|---|---|---|
| `search_knowledge` | RAG na KB da conta (`Rag::Retriever`, top_k=8 → 4 parents). Retorna trechos com relevância. | Scoped por `account_id`. Sem RBAC de usuário (paciente). |
| `clinic_info` | Horários, serviços (só os com ≥1 profissional vinculado), preços, profissionais. Query AR direta, sem RAG. | Scoped por `account_id`. |
| `search_available_slots` | Até 4 slots reais bookáveis para um serviço, respeitando agenda de cada profissional; distribui 2 manhã/2 tarde. | Scoped por `account_id`; valida serviço×profissional. |
| `book_appointment` | Cria `AgendaEvent` em `pending_confirmation`, source `ai_agent`. | Critique pré-exec; anti-duplicação por índice único; auto-inject `patient_id`. |
| `reschedule_appointment` | Reagenda evento existente, volta a `pending_confirmation`. | Critique pré-exec; valida posse na conta. |
| `cancel_appointment` | Cancela evento do paciente da conversa. | Valida posse; status bloqueados. |
| `create_patient_minimal` | Cria ficha mínima (nome + telefone + contact_id); auto-detecta terceiro/família. | **Hard cap 5/contato/dia** (SEC-14, Redis 24h). |
| `find_patient_by_phone` | Busca Patients pelo telefone do Contact (suffix-match 8 dígitos). | Scoped por `account_id`. |
| `confirm_patient_identity` | Vincula `Patient.contact_id` ao Contact após confirmação textual. | Bloqueia se já vinculado a outro contato. |
| `patient_lookup` | Dados do paciente atual (nome, status, alertas críticos). | Resolve via `contact_id` da sessão. |
| `list_appointments` | Próximas consultas do paciente atual (read-only). | Resolve via `contact_id`. |
| `financial_status` | Parcelas pendentes/vencidas + próximo vencimento (read-only). | Nunca negocia/altera; resolve via `contact_id`. |
| `transfer_to_human` | Escala: marca state `escalated`, assina agente disponível, nota privada. | — |
| `notify_staff` | Nota interna privada na conversa (não visível ao paciente). | — |
| `erasure_request` | LGPD art. 18 VI: **registra** pedido (AuditLog + nota interna), NÃO apaga. Execução por `Lgpd::ErasureExecutor` aprovada por humano. | Valida que o Contact pertence à conta (SEC-13). |

> `notify_staff` e `clinic_info` aparecem no `BUILTIN`; os demais com `key` acima.
> A execução real de erasure (`ErasureExecutor`) apaga `PatientMemory`, `Trace`,
> `Feedback`, `ConversationState` — mas **nunca** o `Patient` (CFM exige reter
> prontuário 20 anos).

### 3.2 Tools do Pipeline B (internas, privilegiadas)

Conjunto fixo em `InternalChat::Toolset`. Read-only + 3 mutações com RBAC.
Todas recebem `patient_id`/`agenda_event_id` explícito (não dependem de
`contact_id` de sessão).

| Classe | O que faz | RBAC exigido (`invoking_user`) |
|---|---|---|
| `ClinicInfoTool` | (reaproveitada) horários, serviços, preços, profissionais. | — (info operacional) |
| `InternalSearchPatientTool` | Busca paciente por nome/telefone (até 5). | `patients:view` |
| `InternalListPatientAppointmentsTool` | Lista consultas futuras + passadas de um paciente. | `agenda:view` |
| `InternalBookAppointmentTool` | Cria agendamento em `pending_confirmation`. Paciente NÃO notificado. | `agenda:create_event` |
| `InternalRescheduleAppointmentTool` | Reagenda; volta a `pending_confirmation`. Sem WhatsApp ao paciente. | `agenda:edit_event` |
| `InternalCancelAppointmentTool` | Cancela consulta. Paciente NÃO notificado. | `agenda:cancel_event` |

**Confirmação em 2 turnos** (regra do `InternalChat::SystemPrompt`): a Bea
PROPÕE primeiro e só executa book/reschedule/cancel após a equipe confirmar
("sim"/"confirma"/"pode").

`invoking_user_can?(mod, action)` (em `BaseTool`): admin da conta bypassa;
caso contrário delega a `invoking_user.beclinic_can?(account, mod, action)`
(RBAC Klivy). Retorna `false` se não há invocador humano (Pipeline A).

---

## 4. Providers de LLM (RubyLLM)

- **OpenAI** — default `gpt-4.1-mini` (`DEFAULT_OPENAI_MODEL`).
- **Gemini** — default `gemini-3-flash-preview` (`DEFAULT_GEMINI_MODEL`).

`model_for_provider` resolve: override por conta (`resolver.chat_model`) →
flag de provider → flag de modelo do provider → default.

### 4.1 Fallback Gemini → OpenAI

`with_provider_fallback` tenta o modelo primário; em erro transiente
(`RateLimitError`, `ServerError`, `ForbiddenError`, `ServiceUnavailableError`)
cai para o fallback OpenAI **se** configurado e diferente do primário e com
`openai_api_key` presente. O `Trace` registra qual provider de fato respondeu
(`actual_provider_used`) para dashboards detectarem outage do Gemini.

Sem fallback configurado: **um retry inline** no mesmo modelo após backoff com
jitter (1.5–3.5s, média 2.5s — BE-27, evita thundering herd).

### 4.2 Circuit breaker (BE-24)

`ChatService::CircuitBreaker` (Redis): se o primário falha
`CIRCUIT_BREAKER_THRESHOLD = 5` vezes em `CIRCUIT_BREAKER_WINDOW = 60s`, abre o
circuito e vai **direto** para o fallback por `CIRCUIT_BREAKER_COOLDOWN = 5min`
(TTL no Redis). Fail-open: se o Redis estiver fora, o circuito é tratado como
fechado.

### 4.3 Patch Gemini "thought signature"

Gemini 3 Preview rejeita function calls sem `thoughtSignature`. RubyLLM 1.9.2 não
faz o round-trip; `GeminiThoughtSignaturePatch` (initializer) captura e reanexa a
assinatura. Remover quando RubyLLM suportar nativamente.

### 4.4 Flags relevantes

`CAPTAIN_LLM_PROVIDER` (`openai`/`gemini`), `CAPTAIN_OPEN_AI_MODEL`,
`CAPTAIN_GEMINI_MODEL`, `CAPTAIN_OPEN_AI_API_KEY`, `CAPTAIN_OPEN_AI_ENDPOINT`,
`CAPTAIN_EMBEDDING_MODEL`. Lidas de `InstallationConfig` (3-camadas — ver §9).

---

## 5. Camadas determinísticas de segurança

### 5.1 `Guardrail::Validator` (pós-LLM, sem LLM)

Checagem final por regex/heurística na saída antes de ir ao paciente. Bloqueia:
- **diagnóstico médico** ("você tem X", "isso é Y", hedging com termo clínico);
- **prescrição/dosagem** (fármaco + mg/ml, "tome 500mg", verbos de prescrição);
- **garantia de resultado** ("garanto", "100% de cura", "vai resolver").

Quando viola, substitui pela `SAFE_FALLBACK` e escala (`state.escalate!`).
Custo zero (sem LLM).

### 5.2 `Emergency::Detector` (pré-LLM, sem LLM)

Classificador determinístico por keyword/regex PT-BR que roda **antes do LLM**
(referência Mount Sinai 2026 / Nature Medicine: LLMs subdiagnosticam ~52% de
emergências reais). Filosofia: **0 falso negativo é prioridade**.

- **Emergência clínica → SAMU 192** (`CLINICAL_PATTERNS`): hemorragia, vias
  aéreas, perda de consciência, dor torácica/infarto, convulsão/AVC, anafilaxia,
  intoxicação, febre alta em bebê.
- **Ideação suicida → CVV 188** (`SUICIDAL_PATTERNS`, tem prioridade).

Disparo → `emergency_short_circuit`: template fixo, escala humano, notifica
equipe (`InternalNotifier::EmergencyAlert`, dedup 5min), `Trace` separado.

### 5.3 Sentinel e SentimentAnalyzer — **DESLIGADOS por default**

> **Atenção operacional:** ambos fazem chamada **LLM extra por turno**. Estão
> **OFF por padrão**. É um erro comum achar que estão ativos.

- **`Humanization::Sentinel`** (`CAPTAIN_BEA_SENTINEL_ENABLED`, default off) —
  reflection 1-step LLM-as-judge pós-LLM, **só em turnos high-stakes**
  (`HighStakesDetector`). **Não regenera** a resposta nesta versão; só grava
  verdict em `Trace.guardrail_violations` (`sentinel:ok` / `sentinel:reproved:...`).
  Tem gate de cost cap próprio (BE-26) e anti-injection (SEC-24, fences `<<<...>>>`).
  O `engine.rb` loga no boot se está `ENABLED`/`DISABLED` para evitar a ilusão de
  cobertura.

- **`Humanization::SentimentAnalyzer`** (`CAPTAIN_BEA_SENTIMENT_ENABLED`, default
  off) — 1 chamada LLM curta por mensagem classificando positivo/neutro/negativo.
  No tier free do Gemini (20 RPM) pode estourar a cota; por isso é opt-in. Quando
  desligado, `consecutive_negative_count` não é alimentado e a regra de escalation
  por sentimento negativo persistente fica inerte.

---

## 6. RAG (parent/child + pgvector)

```
Document → IngestDocumentJob (queue :low)
   │  TextExtractor → Rag::Chunker (parent ~grande / child ~300 chars)
   │  EmbeddingClient.embed_batch (fora da transação; cache Redis MGET)
   ▼
ParentChunk (1:N) ChildChunk (com embedding pgvector)

Query → Rag::Retriever
   │  EmbeddingClient.embed(query)
   │  ChildChunk.nearest_to (cosine `<=>`, top_k=8)
   │  promove a parents (dedup, ordena por melhor distância, limit 4)
   ▼
Hit[parent_chunk, best_distance, matched_children]
```

- **`IngestDocumentJob`** — re-rodar no mesmo documento apaga chunks antigos
  (`parent_chunks.destroy_all`) e regenera. Embeddings rodam **fora da transação**
  e o cache é checado em batch (1 Redis MGET vs N GETs — PERF-21).
- **`EmbeddingClient`** — wrapper sobre RubyLLM embeddings, modelo default
  `text-embedding-3-small`. Cache Redis por `model + sha256(text)`, TTL 30 dias.
- **`Rag::Retriever`** — `DEFAULT_TOP_K = 8`, `DEFAULT_PARENT_LIMIT = 4`. Busca
  `ChildChunk` por cosine distance, agrupa por parent.
- **Scoping por conta (defesa em profundidade)** — `ChildChunk` tem `account_id`
  direto; `ParentChunk` não, então o retriever faz JOIN com
  `ai_agent_documents.account_id`. Nenhum chunk de outro tenant retorna mesmo se
  um child escapasse do scope.
- **`Document.status`** — `pending`/`processing`/`processed`/`failed`;
  `MAX_PDF_SIZE = 20MB`.

---

## 7. Crons (registrados em RUNTIME no `engine.rb`)

> **Importante:** os crons da Bea **não** estão em `config/schedule.yml`. São
> criados em runtime via `Sidekiq::Cron::Job.create` dentro de
> `config.after_initialize`, **somente quando `Sidekiq.server?`** (evita entries
> fantasma em console/specs/web boot).

| Cron | Schedule | Fan-out |
|---|---|---|
| `ProactiveOutreachJob` | `0 17 * * *` (17h UTC = 14h SP) | Despacha 1 `ProactiveOutreachPerAccountJob` por conta com Bea habilitada (`RecallFinder`, cap 30/dia/conta) |
| `ConsolidatePatientMemoryJob` | `0 7 * * *` (7h UTC = 4h SP) | 1 `ConsolidatePatientMemoryPerAccountJob` por conta; roda `Memory::Distiller` para perfis destilados |
| `FollowUpDispatcherJob` | `* * * * *` (1 min) | 1 `FollowUpDispatcherPerAccountJob` por conta com ≥1 regra enabled (`CandidateFinder`, janela ±1min) |
| `Health::MonitorJob` | `*/10 * * * *` (10 min) | `Health::Checker` → `Health::Notifier` (dedup TTL 1h por alert.key) |

**Arquitetura fan-out por conta** (ESC-1/ESC-3): o cron raiz só **despacha** um
job por conta; o `PerAccountJob` carrega a lógica real. Em escala (1000+ tenants),
processar sequencialmente excedia o intervalo de 1min e acumulava backlog —
agora o Sidekiq paraleliza N workers.

Limites: `FollowUpDispatcherJob::MAX_PER_ACCOUNT_PER_RUN = 200`,
`PER_CONTACT_COOLDOWN = 2h` (máx. 1 follow-up automático a cada 2h por contato).
`ProactiveOutreachJob::DAILY_PER_ACCOUNT_CAP = 30`.

---

## 8. Modelos de dados

15 modelos em `plugins/ai_agent/app/models/ai_agent/`:

| Modelo | Tabela | Papel |
|---|---|---|
| `Trace` | `ai_agent_traces` | 1 linha por turno: custo (`cost_cents`), latência (`latency_ms`), tokens, `tool_calls`, sentimento, `escalated`/`escalation_reason`, `guardrail_violations`, `short_circuited`. Índice único parcial por `message_id` (idempotência). |
| `AccountSetting` | `ai_agent_account_settings` | Config por conta: `enabled`, `chat_model`, budgets, persona, prompt prefix, `enabled_tools`, médico responsável (CFM 2.454/2026). |
| `GlobalSetting` | `ai_agent_global_settings` | Singleton (`.current`): provider, defaults, teto de custo mensal (`max_monthly_cost_per_account_cents`, 0 = sem cap). |
| `ConversationState` | `ai_agent_conversation_states` | Memória de curto prazo da conversa: `status` (active/escalated/resolved/abandoned), `working_memory`, sentimento, contadores. `escalate!`. |
| `PatientMemory` | `ai_agent_patient_memories` | Memória de longo prazo por `contact_id`: `preferences` + `history` (capped 50). |
| `UsageCounter` | `ai_agent_usage_counters` | Agregado diário por conta (tokens, custo, conversas, tool_calls). `bump!` atômico; `monthly_cost_cents`. |
| `AuditLog` | `ai_agent_audit_logs` | Append-only (`readonly?`), scopes global/account/persona/tool. Usado por config e erasure LGPD. |
| `ToolDefinition` | `ai_agent_tool_definitions` | `key` → metadata + `enabled_globally`. Liga/desliga tool no nível global. |
| `Document` | `ai_agent_documents` | Documento da KB (pdf/text/url), `status` enum, `has_one_attached :pdf_file`. |
| `ParentChunk` | (chunks RAG) | Bloco grande de contexto; promovido a partir dos children no retrieval. |
| `ChildChunk` | `ai_agent_child_chunks` | Bloco ~300 chars com embedding pgvector; `nearest_to` (cosine). |
| `Feedback` | `ai_agent_feedbacks` | Thumbs up/down ligado a um `Trace`. |
| `FollowUpRule` | `ai_agent_follow_up_rules` | Regra configurável de follow-up (trigger, offset, applies_to, cooldown). |
| `FollowUpExecution` | `ai_agent_follow_up_executions` | Registro/idempotência de cada disparo de follow-up. |
| `PersonaTemplate` | (personas) | Template de persona reutilizável (tom/estilo). |
| `InternalNotificationTemplate` | (templates) | Templates editáveis de notificação no Chat Interno (10 default por conta, desativados). |

> Config em **3 camadas** (`ConfigResolver`): `GlobalSetting` (teto) →
> `AccountSetting` (clampado contra o global) → `User`. Valores de conta nunca
> excedem o global.

---

## 9. Configuração, segurança e limites

### 9.1 Flags de configuração (`InstallationConfig`)

| Flag | Default | Efeito |
|---|---|---|
| `CAPTAIN_LLM_PROVIDER` | `openai` | Provider primário do LLM (`openai`/`gemini`). |
| `CAPTAIN_OPEN_AI_MODEL` | `gpt-4.1-mini` | Modelo OpenAI (também é o fallback). |
| `CAPTAIN_GEMINI_MODEL` | `gemini-3-flash-preview` | Modelo Gemini quando provider = gemini. |
| `CAPTAIN_OPEN_AI_API_KEY` | — | Chave OpenAI (habilita fallback). |
| `CAPTAIN_OPEN_AI_ENDPOINT` | — | Base URL OpenAI (proxy/Azure). |
| `CAPTAIN_EMBEDDING_MODEL` | `text-embedding-3-small` | Modelo de embedding do RAG. |
| `CAPTAIN_BEA_SENTINEL_ENABLED` | `false` | Liga Sentinel (LLM-as-judge extra; só high-stakes). |
| `CAPTAIN_BEA_SENTIMENT_ENABLED` | `false` | Liga SentimentAnalyzer (1 LLM extra por mensagem). |
| `CAPTAIN_BEA_INTERNAL_CHAT_SYSTEM_PROMPT` | default interno | System prompt do Pipeline B. |
| `CAPTAIN_BEA_INTERNAL_CHAT_DAILY_LIMIT` | `30` | Respostas da Bea por sala/dia (Pipeline B). |

### 9.2 Cost caps e quotas

- **Cost cap mensal por conta** — `GlobalSetting.max_monthly_cost_per_account_cents`
  (0 = ilimitado); `ConfigResolver#over_monthly_cost_cap?` compara com
  `UsageCounter.monthly_cost_cents`. Gateia o turno e também o Sentinel (BE-26).
- **Captain quota** — a Bea compartilha a cota `captain_responses` do plano; ao
  esgotar, `captain_quota_handoff`.

### 9.3 Rate limits

| Onde | Limite | Janela / TTL |
|---|---|---|
| `RateLimiter` por conversa (Pipeline A) | 60 turnos | 1h |
| `RateLimiter` por conta (Pipeline A) | 2000 turnos | 1 dia |
| `InternalChat::RateLimiter` (Pipeline B) | 30 respostas/sala | dia |
| `CreatePatientMinimalTool` | 5 fichas/contato | 24h (Redis, SEC-14) |
| `FeedbacksController` | 60 req/min/IP | 60s (Redis, SEC-28) |

### 9.4 Circuit breaker

Threshold 5 falhas / janela 60s / cooldown 5min (§4.2). Fail-open em Redis down.

### 9.5 Multi-tenancy (regra dura)

Toda query, broadcast e chave Redis é scoped por `account_id`. Vetores
historicamente sensíveis e suas defesas:
- **Jobs** — `ChatResponseJob`/`RespondJob` recebem `account_id:` e validam que a
  mensagem pertence à conta (MT-5).
- **Tools com ID do LLM** — validam posse na conta antes de mutar.
- **RAG** — filtro `account_id` no scope + JOIN com `ai_agent_documents`.
- **Pipeline B** — `in_reply_to` é resolvido **dentro da mesma sala** (bloqueia
  injection cross-room/cross-tenant no prompt).

---

## 10. Webhooks e eventos

- **Trigger principal** — `Message#after_create_commit` (callback direto, §1.2).
- **Listeners injetados via `to_prepare`** (`engine.rb`): `AgendaEvent`
  (pending_confirmation/cancelled/no_show → notificações no Chat Interno),
  `Conversation` (resolved → reseta `ConversationState` para active),
  `Account`/`Captain::Assistant` (seed/proteção da Beatriz).
- **Pipeline B** — `InternalChat::AiAgentMentionListener` é chamado pelo
  `InternalChat::MessageDispatcher` após persistir a mensagem e registrar as
  menções.
- **Notificações internas (Pipeline A)** — `InternalNotifier::*`
  (EmergencyAlert, OffensiveToneAlert, RefundRequestAlert, RepeatedFailuresAlert,
  AppointmentPendingConfirmation/Cancelled/NoShow/BookingFailed) postam no Chat
  Interno via templates editáveis, com dedup por janela.

---

## Referências

- `plugins/ai_agent/README.md`
- `plugins/ai_agent/lib/ai_agent/engine.rb`
- `plugins/ai_agent/app/services/ai_agent/chat_service.rb`
- `plugins/ai_agent/app/services/ai_agent/tool_registry.rb`
- `docs/01-product/ai-agent-configuration-plan.md` (roadmap de produto)
- `docs/audits/ai-agent-internal-chat-audit.md` (auditoria 2026-05-18, IDs SEC-/BE-/MT-/ESC-/PERF-)
- `docs/adr/0001-llm-provider-fallback.md`, `0002-sentinel-opt-in.md`
</content>
</invoke>
