# Changelog & Handoff — Bea (AI Agent Plugin)

> **Documento de handoff completo** para o programador que vai dar manutenção/evolução ao agente de IA da Klivy ("Bea").
> Última atualização: 2026-05-05.

---

## 📌 Sumário Executivo

Foi adicionado à plataforma Klivy (fork do Chatwoot) um **agente de IA chamado Bea**. Ele atende pacientes de clínicas (odontológicas, estéticas, bem-estar) automaticamente, consultando RAG (PDFs enviados), agenda interna, prontuário e financeiro. Transfere pra humano quando necessário.

**Provider primário**: Gemini (Google AI Studio).
**Fallback automático**: OpenAI (em caso de outage do Gemini).
**Brand visível**: "Bea". **Nome técnico no código**: `ai_agent`.

Todo o trabalho está organizado seguindo **arquitetura limpa em plugin isolado** (padrão `plugins/billing/`). Quase **zero alteração no core**.

---

## 🏗 Estrutura geral do trabalho

### Plugin novo (auto-contido)

```
plugins/ai_agent/
├── lib/
│   ├── ai_agent.rb
│   └── ai_agent/
│       └── engine.rb              # Rails::Engine + hooks
├── config/
│   └── routes.rb                  # rotas do engine (vazio por enquanto)
├── db/
│   └── migrate/                   # 17 migrations próprias do plugin
├── app/
│   ├── models/ai_agent/           # 13 models namespeados
│   ├── services/ai_agent/         # 25+ services
│   ├── jobs/ai_agent/             # 2 jobs
│   └── listeners/ai_agent/        # 1 listener (event dispatcher)
```

### Mudanças no core (mínimas e justificadas)

| Arquivo | O que mudou | Por quê |
|---|---|---|
| [`config/application.rb`](../config/application.rb) | **Já existia** linha de auto-load de plugins. Não foi alterada. | — |
| [`config/routes.rb`](../config/routes.rb) | Adicionadas rotas do super admin: `resource :bea`, `member do; get :bea; patch :bea, action: :update_bea; end`, `resources :ai_agent_documents` (nested em accounts). | UI do super admin precisa de URL. |
| [`config/llm.yml`](../config/llm.yml) | Corrigido typo `aproviders:` → `providers:`. Removido `coming_soon: true` dos modelos Gemini. | Gemini estava marcado como "em breve" e o typo deixava `Llm::Models.providers` retornando nil. |
| [`config/installation_config.yml`](../config/installation_config.yml) | Adicionadas 3 entradas: `CAPTAIN_GEMINI_API_KEY`, `CAPTAIN_GEMINI_MODEL`, `CAPTAIN_LLM_PROVIDER`. | Permitir super admin configurar Gemini via UI. |
| [`lib/llm/config.rb`](../lib/llm/config.rb) | Adicionada linha `config.gemini_api_key = ...` no bloco RubyLLM. OpenAI continua intacto. | RubyLLM precisa receber a chave Gemini. |
| [`Gemfile`](../Gemfile) | Adicionado `gem 'pdf-reader', '~> 2.12'`. | Extração de texto de PDFs para RAG. |
| [`app/controllers/super_admin/app_configs_controller.rb`](../app/controllers/super_admin/app_configs_controller.rb) | Whitelist `'captain'` ampliada para incluir as 3 novas chaves Gemini + `CAPTAIN_EMBEDDING_MODEL`. | Sem isso, salvar via super admin é bloqueado. |
| [`app/controllers/super_admin/accounts_controller.rb`](../app/controllers/super_admin/accounts_controller.rb) | Adicionadas actions `bea` e `update_bea` + helpers privados (`bea_setting_params`, `clamp_against_global!`). | UI de configuração da Bea por conta. |
| [`app/controllers/super_admin/bea_controller.rb`](../app/controllers/super_admin/bea_controller.rb) | **Novo**. | Página global "Bea" no super admin. |
| [`app/controllers/super_admin/ai_agent_documents_controller.rb`](../app/controllers/super_admin/ai_agent_documents_controller.rb) | **Novo**. | Upload/listagem de PDFs por conta. |
| [`app/views/super_admin/application/_navigation.html.erb`](../app/views/super_admin/application/_navigation.html.erb) | Adicionado item "Bea" na sidebar; `"bea"` e `"ai_agent_documents"` adicionados à lista de exclusão do scan automático do Administrate. | Sem a exclusão, a sidebar quebrava com `No route matches`. |
| [`app/views/super_admin/accounts/show.html.erb`](../app/views/super_admin/accounts/show.html.erb) | Adicionado botão "Configurar Bea" no header. | Acesso à página per-account. |
| [`app/views/super_admin/bea/show.html.erb`](../app/views/super_admin/bea/show.html.erb) | **Nova**. | Página de configuração global. |
| [`app/views/super_admin/accounts/bea.html.erb`](../app/views/super_admin/accounts/bea.html.erb) | **Nova**. | Página de configuração por conta. |
| [`app/views/super_admin/ai_agent_documents/index.html.erb`](../app/views/super_admin/ai_agent_documents/index.html.erb) | **Nova**. | Upload e listagem de PDFs. |

### O que **NÃO** foi tocado no core (por princípio)

- ❌ Models do Chatwoot (`Account`, `User`, `Conversation`, `Message`, `Inbox`, `Contact`) — apenas estendidos via `Account.class_eval` dentro do engine `to_prepare`, **nunca editados diretamente**.
- ❌ Controllers de API do Chatwoot.
- ❌ Vistas do front-end Vue (Captain UI continua funcionando como antes).
- ❌ Sistema de eventos / dispatcher base (apenas registramos um listener via `prepend`).
- ❌ Schemas existentes (todas as nossas tabelas têm prefixo `ai_agent_*`).
- ❌ Assets/CSS/JS.

---

## 📊 Linha do tempo de fases entregues

| # | Fase | O que entregou |
|---|---|---|
| **0** | Habilitar Gemini Provider | RubyLLM aceita `gemini_api_key`; super admin pode configurar via UI. |
| **1** | Scaffold do plugin `ai_agent` | Engine, 6 models de configuração, ConfigResolver com hierarquia 3 camadas + clamp. |
| **1.5a** | UI Super Admin global "Bea" | Item na sidebar (ícone robô); aba Provider funcional; modelos como input livre. |
| **1.5b** | UI Super Admin per-account | Página `/super_admin/accounts/:id/bea` com status/budget/persona/tools/audit log. |
| **2** | RAG parent/child | Upload PDF → chunking hierárquico (parent ~1500 chars, child ~300 + overlap 50) → embeddings → retriever pgvector com índice IVFFlat. |
| **3** | Single-agent + tools | ChatService com loop de tool-calling Gemini; webhook integration via listener; AgentBot "Bea"; indicador "digitando…"; upload PDF UI. |
| **4** | Tools de ação read-only | 6 tools: search_knowledge, transfer_to_human, patient_lookup, list_appointments, financial_status, notify_staff. |
| **5** | Humanização + guardrails | Sentiment analyzer (LLM leve); EscalationRules (5 sinais); Validator (diagnóstico/prescrição/garantia); 3 personas builtin. |
| **6** | Observabilidade + feedback | Trace por turno (latência/tokens/custo); Pricing por modelo; Feedback 👍/👎; dashboard com 8 KPIs. |
| **7** | Hardening | Rate limit (Redis); fallback Gemini→OpenAI; cache de embeddings (30d); runbook completo. |

Detalhe de cada fase com critérios de aceite e arquivos entregues está em [`docs/01-product/ai-agent-action-plan.md`](01-product/ai-agent-action-plan.md).

---

## 📁 Inventário completo dos arquivos criados/alterados

### Migrations (17 — todas em `plugins/ai_agent/db/migrate/`)

| Arquivo | Tabela | Notas |
|---|---|---|
| `20260505000001_create_ai_agent_global_settings.rb` | `ai_agent_global_settings` | Singleton — config global (provider, modelo, tetos, persona default). |
| `20260505000002_create_ai_agent_account_settings.rb` | `ai_agent_account_settings` | FK única em `account_id`. Override por conta. |
| `20260505000003_create_ai_agent_persona_templates.rb` | `ai_agent_persona_templates` | Templates de persona com vertical (dental/aesthetic/wellness/general). |
| `20260505000004_create_ai_agent_tool_definitions.rb` | `ai_agent_tool_definitions` | Catálogo de tools disponíveis no tenant. |
| `20260505000005_create_ai_agent_audit_logs.rb` | `ai_agent_audit_logs` | Append-only — quem mudou o quê quando. |
| `20260505000006_create_ai_agent_usage_counters.rb` | `ai_agent_usage_counters` | Tokens/custo por dia/conta. Bump atômico via `update_all`. |
| `20260505000007_create_ai_agent_documents.rb` | `ai_agent_documents` | PDFs com `has_one_attached :pdf_file` (ActiveStorage). |
| `20260505000008_create_ai_agent_parent_chunks.rb` | `ai_agent_parent_chunks` | Blocos grandes (geração). |
| `20260505000009_create_ai_agent_child_chunks.rb` | `ai_agent_child_chunks` | Blocos pequenos com `vector(1536)` + índice IVFFlat. |
| `20260505000010_create_ai_agent_conversation_states.rb` | `ai_agent_conversation_states` | Memória curta por conversa. |
| `20260505000011_create_ai_agent_patient_memories.rb` | `ai_agent_patient_memories` | Memória longa por contact_id. |
| `20260505000012_seed_ai_agent_builtin_tools.rb` | (seed) | Insere `search_knowledge` + `transfer_to_human`. |
| `20260505000013_seed_ai_agent_action_tools.rb` | (seed) | Insere as 4 tools de ação. |
| `20260505000014_add_sentiment_to_conversation_states.rb` | (alter) | `last_sentiment_score`, `consecutive_negative_count`, etc. |
| `20260505000015_seed_ai_agent_persona_templates.rb` | (seed) | Insere 3 personas builtin. |
| `20260505000016_create_ai_agent_traces.rb` | `ai_agent_traces` | 1 row por turno LLM. |
| `20260505000017_create_ai_agent_feedbacks.rb` | `ai_agent_feedbacks` | 👍 (+1) / 👎 (-1). |

> ⚠️ **Importante**: o engine appenda essas migrations ao path padrão via `initializer :append_ai_agent_migrations`. Rodar `rails db:migrate` normal pega elas.

### Models (13 — `plugins/ai_agent/app/models/ai_agent/`)

- `global_setting.rb` — singleton (`AiAgent::GlobalSetting.current`).
- `account_setting.rb` — `belongs_to :account`, FK única.
- `persona_template.rb` — vertical enum, system_prompt.
- `tool_definition.rb` — key, name, enabled_globally.
- `audit_log.rb` — append-only, método de classe `record(...)`.
- `usage_counter.rb` — bump atômico por `update_all`.
- `document.rb` — `has_one_attached :pdf_file`, validação custom (sem dep nova de gem).
- `parent_chunk.rb` — `belongs_to :document`, `before_save :recompute_char_count`.
- `child_chunk.rb` — `belongs_to :parent_chunk`, embedding pgvector, scope `nearest_to`.
- `conversation_state.rb` — short-term, `for(account:, conversation_id:)`, `escalate!`.
- `patient_memory.rb` — long-term, history capped em 50.
- `trace.rb` — registro por turno LLM.
- `feedback.rb` — rating ±1 + scopes `positive`/`negative`.

### Services (25+ — `plugins/ai_agent/app/services/ai_agent/`)

| Caminho | Função |
|---|---|
| `config_resolver.rb` | Hierarquia 3 camadas global→account com clamp. |
| `chat_service.rb` | Orquestrador principal. Pipeline: track repetition → sentiment → escalation → LLM → guardrail → trace. |
| `prompt_builder.rb` | Monta system prompt em 4 camadas (persona + prefix + memória + state). |
| `tool_registry.rb` | Mapeia keys → classes Ruby. |
| `agent_bot_identity.rb` | Cria/retorna `AgentBot "Bea"` global (sender das messages). |
| `pricing.rb` | Tabela hardcoded USD/1M tokens → BRL cents. |
| `rate_limiter.rb` | Redis counters por conversa (60/h) e conta (2000/dia). |
| `rag/chunker.rb` | Parent/child splitter. |
| `rag/retriever.rb` | Top-K children → unique parents por distância cosseno. |
| `documents/text_extractor.rb` | PDF (pdf-reader) ou URL (Faraday + Html2Text). |
| `llm/embedding_client.rb` | Wrapper RubyLLM + cache Redis 30 dias. |
| `humanization/sentiment_analyzer.rb` | LLM leve, parse `LABEL=... SCORE=... CONFIDENCE=...`. |
| `humanization/escalation_rules.rb` | 5 sinais: explicit_human_request, urgent_clinical_signal, consecutive_negative_sentiment, consecutive_tool_failures, user_loop. |
| `guardrail/validator.rb` | Bloqueia diagnóstico/prescrição/garantia via regex. |
| `tools/base_tool.rb` | Herda `RubyLLM::Tool`, recebe Context. |
| `tools/search_knowledge_tool.rb` | RAG via Retriever. |
| `tools/transfer_to_human_tool.rb` | Escalada explícita. |
| `tools/patient_lookup_tool.rb` | Resolve `Patient` da conversa atual. |
| `tools/list_appointments_tool.rb` | Lista próximas consultas (read-only). |
| `tools/financial_status_tool.rb` | Parcelas pendentes/em atraso (read-only). |
| `tools/notify_staff_tool.rb` | Cria private note na conversa + registra em PatientMemory. |

### Jobs (2 — `plugins/ai_agent/app/jobs/ai_agent/`)

- `ingest_document_job.rb` — pipeline atômico extract → chunk → embed → persist. Idempotente (rerun apaga chunks antigos).
- `chat_response_job.rb` — async worker. typing_on (dispatch event) → ChatService → post outgoing message → typing_off em `ensure`.

### Listeners (1 — `plugins/ai_agent/app/listeners/ai_agent/event_listeners/`)

- `message_listener.rb` — Singleton que recebe `message_created` do AsyncDispatcher do Chatwoot. Aplica filtros (incoming, Bea ativa, sem assignee humano, dentro do rate limit) e enfileira `ChatResponseJob`.

### Views novas (3)

- `app/views/super_admin/bea/show.html.erb` — config global.
- `app/views/super_admin/accounts/bea.html.erb` — config per-account.
- `app/views/super_admin/ai_agent_documents/index.html.erb` — upload PDFs.

### Documentação (3)

- `docs/01-product/ai-agent-action-plan.md` — plano completo + status (v1.2).
- `docs/03-engineering/bea-runbook.md` — runbook operacional.
- `docs/ai-agent-changelog.md` — este documento.

---

## ⚙️ Hierarquia de configuração (3 camadas)

```
┌────────────────────────────────────────────────────────────┐
│ 1. GLOBAL  (Super Admin → "Bea" na sidebar)                │
│    ─ provider (gemini/openai)                              │
│    ─ chaves de API + modelos default                       │
│    ─ tetos máximos: tokens/conversa, custo/conta/mês       │
│    ─ persona default                                       │
│    ─ guardrails globais                                    │
└────────────────────────────────────────────────────────────┘
                          ▼ herda
┌────────────────────────────────────────────────────────────┐
│ 2. ACCOUNT (Super Admin → Contas → [conta] → Configurar Bea)│
│    ─ on/off por conta                                      │
│    ─ tier de modelo (clamped pelo global)                  │
│    ─ budget mensal de tokens                               │
│    ─ persona override                                      │
│    ─ tools whitelist                                       │
│    ─ system prompt prefix                                  │
└────────────────────────────────────────────────────────────┘
                          ▼ herda
┌────────────────────────────────────────────────────────────┐
│ 3. USER OPERATIONAL (Captain UI da própria conta)          │
│    Reutiliza UI existente:                                 │
│    ─ FAQs, Documentos, Cenários, Playground                │
│    ─ Caixas de Entrada, Ferramentas custom                 │
│    NÃO pode trocar provider/modelo/budget                  │
└────────────────────────────────────────────────────────────┘
```

Implementação: `AiAgent::ConfigResolver` em [`plugins/ai_agent/app/services/ai_agent/config_resolver.rb`](../plugins/ai_agent/app/services/ai_agent/config_resolver.rb).

---

## 🔄 Pipeline de uma resposta da Bea

```
mensagem incoming chega na inbox do Chatwoot
  ↓
Chatwoot dispatch (message.created)
  ↓
AsyncDispatcher.listeners (Chatwoot enterprise + AiAgent)
  ↓
AiAgent::EventListeners::MessageListener
  ├─ filter: incoming? não-private? content presente?
  ├─ filter: Bea ativa na conta?
  ├─ filter: conversa não escalada?
  ├─ filter: sem assignee humano?
  └─ rate_limit (Redis): 60/h por conv, 2000/dia por conta
  ↓
AiAgent::ChatResponseJob (Sidekiq, queue :default)
  ├─ typing_on (dispatch CONVERSATION_TYPING_ON)
  ├─ build_history (últimas 20 mensagens não-private)
  └─ ChatService.respond:
       1. track_message_repetition (working_memory.repeat_count)
       2. apply_sentiment (LLM leve, salva no state)
       3. EscalationRules.evaluate
          ├─ explícito ("falar com humano") ──→ early_handoff (SEM LLM)
          ├─ urgente ("dor forte")            ──→ early_handoff (SEM LLM)
          ├─ negativo 2+ turnos              ──→ early_handoff (SEM LLM)
          ├─ tool_failures 2+                ──→ early_handoff (SEM LLM)
          └─ loop 3x mesma msg               ──→ early_handoff (SEM LLM)
       4. PromptBuilder.system_instructions (4 camadas)
       5. with_provider_fallback:
          ├─ try Gemini (modelo configurado)
          └─ on RateLimitError/ServerError/Forbidden → retry OpenAI
          ├─ tools: search_knowledge / transfer_to_human / patient_lookup / list_appointments / financial_status / notify_staff
       6. Guardrail::Validator
          ├─ medical_diagnosis ──→ replace by safe template + escalate
          ├─ prescription      ──→ replace by safe template + escalate
          └─ guarantee         ──→ replace by safe template + escalate
       7. record_usage (UsageCounter.bump!) — custo real via Pricing
       8. persist_trace (latência, tokens, model, tool_calls, sentiment, escalated, violations)
  ├─ post_reply (Message outgoing, sender: AgentBot Bea)
  └─ ensure: typing_off (dispatch CONVERSATION_TYPING_OFF)
  ↓
Frontend recebe via ActionCable → exibe resposta + indicador de digitação
```

---

## 🧰 Ferramentas (tools) disponíveis para a Bea

| Tool key | Nome | Tipo | O que faz |
|---|---|---|---|
| `search_knowledge` | Buscar conhecimento | RAG | Consulta `AiAgent::Document` chunks via pgvector. |
| `transfer_to_human` | Transferir para humano | Escalada | Marca state como `escalated`, registra evento. |
| `patient_lookup` | Buscar paciente atual | Read | Resolve `Patient` por contact_id da conversa. |
| `list_appointments` | Listar consultas | Read | Próximas consultas em `AgendaEvent`. |
| `financial_status` | Situação financeira | Read | `Installment` pendentes/atrasados do paciente. |
| `notify_staff` | Notificar equipe | Write (private) | Cria nota interna privada na conversa. |

Todas estão no banco como `AiAgent::ToolDefinition` (`builtin: true`) e instanciáveis via `AiAgent::ToolRegistry`.

**NÃO** existem ainda (planejadas — Fase 4.5):
- Booking real de consultas (criar/cancelar `AgendaEvent`)
- Operações financeiras de escrita (registrar pagamento)
- Google Calendar (OAuth necessário)

---

## ⚠️ Pontos de atenção / problemas conhecidos

### 🔴 Cuidados ao adicionar rotas no super admin

O Administrate (framework do super admin) faz **scan automático de TODOS os controllers `super_admin/*`** na sidebar. Tenta gerar URL pra cada um via `super_admin_<name>_path`. Se o controller for nested ou singular sem rota standalone, **a sidebar inteira quebra** com `ActionView::Template::Error: No route matches`.

**Solução**: editar [`app/views/super_admin/application/_navigation.html.erb:35`](../app/views/super_admin/application/_navigation.html.erb#L35) e adicionar o nome do resource na lista de exclusão:

```erb
<% next if ["account_users", ..., "bea", "ai_agent_documents", "NOVO_RESOURCE"].include?  resource.resource %>
```

**Já tratados** atualmente: `bea`, `ai_agent_documents`, `klivy_widgets`, `migrations`, `help_*`.

### 🔴 Auto-reload de dev pode acumular state

Em sessões longas de `rails s` (ou `foreman start`), o processo Puma pode acumular memória de reloads do Zeitwerk e ficar em **100% CPU em loop infinito**. Sintoma: todas as requests dão timeout.

**Diagnóstico**:
```bash
ps aux | grep puma | grep -v grep
# Se vir > 90% CPU em status R por minutos:
```

**Solução**:
```bash
# pega PID do puma
kill -9 <PID_PUMA>
# limpa portas órfãs
lsof -ti:3036 | xargs kill -9 2>/dev/null  # vite
lsof -ti:3002 | xargs kill -9 2>/dev/null  # whatsapp bridge
# remove pidfiles
rm -f tmp/pids/*.pid
# reinicia
foreman start -f Procfile.dev
```

**Prevenção**: o `engine.rb` foi escrito com cuidado pra evitar isso — `AsyncDispatcher.prepend` está em `initializer` (1× boot) em vez de `to_prepare` (toda request); associations em `Account` são protegidas com `unless reflect_on_association`.

### 🔴 Mudar embedding model exige re-embed completo

O schema é `vector(1536)` (OpenAI `text-embedding-3-small`). Mudar para um modelo com dimensão diferente (Gemini text-embedding-004 = 768; gemini-embedding-001 = 3072) **quebra todos os embeddings existentes**. Plano:

1. Migration adicionando coluna nova com nova dimensão OU substituir tipo da coluna.
2. Job que re-processa todos `AiAgent::Document` → `IngestDocumentJob.perform_later`.
3. Limpar cache: `$alfred.with { |c| c.keys('ai_agent:emb:*').each { |k| c.del(k) } }`.

### 🟡 Quota Gemini

Free tier do Google AI Studio é generoso (15 RPM, 1500/dia, 1M tokens) mas pequeno pra produção. Sintomas:

- `RubyLLM::RateLimitError "exceeded your current quota"` → quota diária esgotou
- `RubyLLM::ForbiddenError "project denied access"` → modelo exige billing habilitado

**Mitigação atual**: fallback automático pra OpenAI (já implementado). Configurar OpenAI key como rede de proteção.

### 🟡 Auditoria mostra chave de API

O `AuditLog` registra mudanças em `InstallationConfig`. Pra evitar vazar a chave em log, [`super_admin/bea_controller.rb`](../app/controllers/super_admin/bea_controller.rb) tem `redact_for_audit` que substitui chaves por `AIza…XYZ4`. **NÃO REMOVA** essa redação.

### 🟡 Models `Patient`, `Installment`, `AgendaEvent` são de outros plugins

As tools `patient_lookup`, `list_appointments`, `financial_status` dependem de:

- `Patient` — `plugins/patients`
- `AgendaEvent` — `plugins/agenda`
- `Installment` — `plugins/financial`

Se algum desses plugins for removido/refatorado/renomeado, as tools quebram silenciosamente (retornam "modelo não disponível"). Cada tool tem `defined?(::Model)` checks pra evitar crash.

### 🟡 Rate limit silencioso

Quando o paciente excede o rate limit, **a Bea simplesmente não responde** (silent drop). Não envia mensagem de erro ao paciente. Isso é proposital (defesa contra spam) mas pode confundir o atendente que vê a conversa "em silêncio". Logs ficam em `[AiAgent] rate limited:`.

### 🟡 Listener prepend no AsyncDispatcher

O engine faz `AsyncDispatcher.prepend(AiAgent::DispatcherExtension)` no `initializer :ai_agent_register_dispatcher_extension`. Se o **enterprise core** prepender DEPOIS, a ordem de listeners pode mudar. Validar com:

```ruby
AsyncDispatcher.new.listeners.map(&:class)
# deve incluir AiAgent::EventListeners::MessageListener
```

---

## 🩺 Como debugar problemas comuns

### Bea não está respondendo numa conversa

```ruby
# rails console
conv_id = 1234
acc = Conversation.find(conv_id).account

# 1. Bea está ativa?
acc.ai_agent_setting&.enabled?
# false → ative em /super_admin/accounts/:id/bea

# 2. Conversa está escalada?
state = AiAgent::ConversationState.find_by(conversation_id: conv_id)
state&.status
# "escalated" → reset com state.update!(status: 'active')

# 3. Tem assignee humano?
Conversation.find(conv_id).assignee_id
# se ≠ nil, listener pula. Desatribua se quiser Bea de volta.

# 4. Rate limited?
AiAgent::RateLimiter.new(account_id: acc.id, conversation_id: conv_id).conv_count
# se > 60, esperar a janela passar (TTL 1h)

# 5. Job na fila?
# vá em /monitoring/sidekiq e filtre por ChatResponseJob
```

### Dashboard mostra deflection rate baixa

```ruby
# Quais razões de escalada nos últimos 100 turnos?
AiAgent::Trace.order(created_at: :desc).limit(100).pluck(:escalation_reason).tally
# Padrão saudável: maioria sem reason (= não escalada).
```

### Custo subindo

```ruby
# Por modelo, últimos 7 dias:
AiAgent::Trace.where(created_at: 7.days.ago..)
              .group(:model)
              .sum(:cost_cents)
```

Se Gemini estiver `0` cents e OpenAI alto: outage de Gemini → fallback ativando muito.

### Resposta vazia ou estranha

```ruby
# Pegue o trace mais recente
trace = AiAgent::Trace.where(conversation_id: <id>).order(created_at: :desc).first
puts trace.attributes.except('tool_calls', 'guardrail_violations').to_yaml
puts "tool_calls: #{trace.tool_calls.inspect}"
puts "violations: #{trace.guardrail_violations.inspect}"
```

### Reprocessar documento (após editar PDF)

```ruby
doc = AiAgent::Document.find(<id>)
AiAgent::IngestDocumentJob.perform_later(doc.id)
# o job é idempotente: apaga chunks antigos antes
```

### Limpar cache de embeddings

```ruby
keys = $alfred.with { |c| c.keys('ai_agent:emb:*') }
$alfred.with { |c| c.del(*keys) } if keys.any?
```

### Forçar provider em runtime (debug)

```ruby
InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER').update!(value: 'openai')
Llm::Config.reset!
# próxima chamada usa OpenAI
```

### LGPD — apagar dados de um paciente

```ruby
contact_id = <id_do_chatwoot_contact>
account_id = <id_da_conta>

AiAgent::PatientMemory.where(account_id:, contact_id:).destroy_all
AiAgent::Trace.where(account_id:, contact_id:).destroy_all
AiAgent::Feedback.where(account_id:, contact_id:).destroy_all
# ConversationState é por conversation_id; ver via Conversation.where(contact_id: ...).pluck(:id)
```

---

## ✅ Checklist pra colocar em produção

1. ✅ **Configurar Gemini API key** em `/super_admin/bea` (campo "Gemini API Key").
2. (recomendado) **Configurar OpenAI API key** — vira fallback automático em outage.
3. **Habilitar Bea em uma conta**: Super Admin → Contas → [conta] → Configurar Bea → marcar "Bea ativa".
4. **Selecionar persona**: dental / aesthetic / wellness.
5. (recomendado) **Definir budget mensal de tokens** enquanto valida custo real (10M tokens é ~R$ 8 com Gemini Flash).
6. **Subir 1-3 PDFs** com FAQs/políticas em `/super_admin/accounts/:id/ai_agent_documents`.
7. **Aguardar status** dos PDFs ir pra `processed` (acompanha em background, alguns segundos).
8. **Mandar mensagem de teste** numa inbox dessa conta. Bea responde com indicador "digitando…".
9. **Acompanhar `/super_admin/bea`** por 7 dias pra ver: deflection rate, custo, escaladas, sentimento, top tools.

Em caso de problema, consultar [`docs/03-engineering/bea-runbook.md`](03-engineering/bea-runbook.md) ou os snippets de debug acima.

---

## 🚧 O que ainda falta (pendências)

| # | Item | Bloqueia produção? | Esforço |
|---|---|---|---|
| **P1** | **Booking com guardrails (Fase 4.5)** — criar/remarcar consultas em `pending_confirmation`, validar conflitos | Não (read-only cobre 80%) | Médio |
| **P2** | **Google Calendar OAuth** — integração real com calendário Google | Não (`AgendaEvent` interno cobre) | Alto |
| **P3** | **Endpoint público de feedback** — paciente avaliar 👍/👎 no widget | Não | Baixo |
| **P4** | **Health endpoint + alertas** — `GET /api/v1/ai_agent/health` + Slack/email quando deflection cai | Não | Médio |
| **P5** | **A/B testing entre personas** — comparar CSAT por persona | Não | Médio |
| **P6** | **Honra de `tone_settings` no PromptBuilder** — hoje só `system_prompt` é usado | Não | Trivial |
| **P7** | **Incremento real de `consecutive_tool_failures`** — coluna criada e EscalationRules considera, mas falta wiring | Não | Trivial |
| **P8** | **Renomear `plugins/agenda` → `schedule` e `plugins/ajuda` → `help`** — débito técnico de nomenclatura PT-BR | Não | Médio (busca/substituição massiva) |
| **P9** | **Models não usados ainda**: `Agent`, `ConversationStateSummary` previstos no plano original mas não criados | Não | — |
| **P10** | **Integração Langfuse externa** — Captain já tem instrumentation; reuso direto é trivial | Não | Médio |
| **P11** | **UI da própria conta (rebrand Captain → Bea)** — o usuário-cliente continua vendo "BEA" no menu lateral, vindo do Captain. Refinar visual com tom/cor da Klivy | Não | Médio |

---

## 🎯 Convenções e padrões usados

### Clean architecture

- **Pasta isolada em `plugins/ai_agent/`** seguindo padrão de `plugins/billing/`.
- **Engine Rails** com `isolate_namespace` — não polui constantes globais.
- **Camadas**: controllers / services / models / jobs / listeners. **Sem cross-pollination** (models não fazem HTTP, services não tocam params).
- **Hooks no core via `to_prepare`** (`Account.class_eval`) — única forma de estender o Chatwoot.

### Naming

- **Código em inglês**: pastas (`ai_agent`), classes (`AiAgent::ChatService`), tabelas (`ai_agent_*`), rotas (`/api/v1/ai_agent/...`).
- **UI em português**: strings nas views, mensagens da Bea, runbook (i18n proper fica como melhoria futura).
- **Brand "Bea" só aparece em strings de UI, nunca em código** — separação `ai_agent` (técnico) vs "Bea" (marca) é deliberada (vide [`docs/01-product/ai-agent-action-plan.md`](01-product/ai-agent-action-plan.md) seção "Brand vs Código").

### Defesa em camadas (segurança da resposta)

Cada turno passa por **5 camadas** de proteção:

1. **EscalationRules** (pré-LLM, regex) — evita LLM em casos óbvios de escalada
2. **Sentiment** (pré-LLM, LLM leve) — detecta frustração latente
3. **Persona** (no prompt) — define tom e limites de comportamento
4. **TransferToHumanTool** (durante LLM) — Bea pode decidir escalar sozinha
5. **Guardrail::Validator** (pós-LLM, regex) — bloqueia diagnóstico/prescrição/garantia

### Idempotência e atomicidade

- `IngestDocumentJob` apaga chunks antigos antes de criar novos — re-rodar é seguro.
- `UsageCounter.bump!` usa `update_all` com SQL puro — atômico, sem race condition.
- `AgentBotIdentity.ensure!` usa `find_or_create_by!` — idempotente.

---

## 📚 Arquivos de referência rápida

| Doc | Quando consultar |
|---|---|
| [`docs/01-product/ai-agent-action-plan.md`](01-product/ai-agent-action-plan.md) | Plano completo, status fase a fase, KPIs, decisões de design (12 decisões registradas). |
| [`docs/03-engineering/bea-runbook.md`](03-engineering/bea-runbook.md) | Operações: ligar/desligar, troubleshooting, LGPD, limites, debug. |
| [`docs/ai-agent-changelog.md`](ai-agent-changelog.md) | Este arquivo — handoff completo. |

---

## 🔢 Estatísticas do trabalho entregue

- **17 migrations**
- **13 models**
- **25+ services**
- **2 jobs**
- **1 listener**
- **3 controllers** novos no super admin
- **3 views** novas no super admin
- **6 tools** ativas para a Bea
- **3 personas** builtin (dental/aesthetic/wellness)
- **9 arquivos do core** modificados (mudanças mínimas)
- **3 documentos** de produto/engenharia

Tudo seguindo o princípio de **plugin isolado**, **zero alteração de comportamento existente** do Chatwoot, e **clean architecture**.

---

**Versão deste documento**: 1.0
**Data**: 2026-05-05
**Geração**: handoff completo pra programador.
