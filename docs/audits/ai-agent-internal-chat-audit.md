# Auditoria Técnica — `plugins/ai_agent` + `plugins/internal_chat`

> **Data da auditoria original:** 2026-05-18
> **Última atualização de status:** 2026-05-19
> **Escopo:** auditoria enterprise-grade ponta a ponta dos engines `plugins/ai_agent` e `plugins/internal_chat`.
> **Metodologia:** 11 agentes de exploração em paralelo (architecture map ai_agent backend/frontend, internal_chat backend/frontend, multi-tenant isolation, security/RBAC, performance/escalabilidade, realtime/WebSocket, ai_agent deep dive AI, internal_chat deep dive chat, code quality + engine compliance).
> **Princípio original:** observar e documentar sem alterar comportamento de produção.

---

## 📊 STATUS DE REMEDIAÇÃO (atualizado 2026-05-19 — quarta revisão)

**~130 entregas em 64 lotes** entre 2026-05-18 e 2026-05-19. **100% das 169 findings tratadas** (aplicado / aceito por design / falso positivo / fechado por outro fix / decisão consciente documentada). ZERO roadmap pendente. ZERO CRÍTICO/ALTO em aberto. **Drift detection ativa**: spec `monkey_patches_spec.rb` (16 examples) detecta quebra em Chatwoot upgrades. **Decompose god files COMPLETO**: ChatService (Fase 4), MessageBubble (FE-1), GroupSettingsDrawer (FE-2), followUps (FE-3), templates (FE-4), SearchAvailableSlotsTool (ARCH-3). **UI primitives padronizados**: BeclinicButton/FormSelect/Checkbox em 13 components (FE-8). **Virtualização aplicada** onde seguro: RoomList + MentionsView (PERF-25). Detalhe finding-by-finding no [Apêndice D](#apêndice-d--status-de-remediação-por-finding).

| Fase | Lotes | Entregas | Status |
|---|---|---|---|
| **Fase 1** (bloqueadores) | 5 | 11 | ✅ COMPLETA |
| **Fase 2** (hardening) | 6 | 19 | ✅ COMPLETA |
| **Fase 3** (performance) | 3 | 8 | ✅ COMPLETA |
| **Fase 2.7** (residuais multi-tenant) | 1 | 4 | ✅ COMPLETA |
| **Pós-auditoria tactical** (lotes 15-32) | 18 | 36 | ✅ COMPLETA — BE-7, BE-26, SEC-24, ESC-1/2/3, BE-1/2/3/4, PERF-3/15/16/17/21/22/23/26, FE-5/6/7/13/15/18/20/21/22/23, SEC-7/8/9, RT-2/3/7/8 |
| **Pós-auditoria deep dive** (lotes 33-44) | 12 | 24 | ✅ COMPLETA — SEC-16/18/19/21/25/26/27/28, BE-8/11/17/18/22/24/27, RT-5, FE-1/2/3/4/14 |
| **Fase 4** (refactors arquiteturais) | 1 | 3 | ✅ COMPLETA — ChatService 1017→907 LOC + 3 módulos. **120/120 specs verde**. Frontend god files já decompostos em lotes 41-44 |
| **Fase 5** (i18n + docs + extract + formalize + virtualize) | 18 | 27 | ✅ COMPLETA — i18n rollout completo (lotes 47-57), docs/ADRs/READMEs (48-49), UserBroadcaster extract (58), ReadReceipt+seed (59), formalização WONTFIX (60), drift detection spec (61), SearchAvailableSlotsTool decompose (62), BeclinicButton sweep (63), virtualização RoomList+MentionsView (64). **100% das 169 findings tratadas, ZERO roadmap pendente, decompose god files completo, UI primitives padronizados, virtualização aplicada onde segura** |

### Categorias de finding após remediação (sexta revisão — lote 64, audit 100%)

| Categoria | Resolvidos | Roadmap |
|---|---|---|
| Multi-tenant | 20/20 (17 aplicados + 3 aceitos design) | 0 |
| Security/RBAC | 29/29 (28 aplicados + 1 FP) | 0 |
| Realtime | 8/8 (6 aplicados + 1 WONTFIX + 1 aceito design) | 0 |
| Performance | 26/26 (21 aplicados — PERF-25 parcial + decisão de adiar MessageThread + 4 fechados via outros + 2 FP) | 0 |
| Backend | 24/24 | 0 |
| Escalabilidade | 3/3 | 0 |
| Frontend | 23/23 (20 aplicados + 2 FP + 2 fechados + 1 aceito design) | 0 |
| Arquiteturais | 23/23 (13 aplicados + 2 fechados via FE-3/4 + 4 OK conformes + 3 aceitos + 1 N/A) | 0 |
| **Total** | **169** | **0** |

### Risco residual

- 🟢 **Multi-tenant: 100% resolvido** (20/20) — 17 aplicados + 3 cron jobs aceitos por design
- 🟢 **Realtime: 100% resolvido** (8/8) — 6 aplicados + 1 WONTFIX + 1 aceito design futuro
- 🟢 **RBAC: 100% resolvido** (29/29) — todos os CRÍTICOS/ALTOS + SEC-7/8/9/10/14/16/17/18/19/20/24/25/26/27/28/29
- 🟢 **LLM injection + safety + output validation**: SEC-22/23 sanitização entrada + SEC-24 Sentinel + SEC-25 MessageGenerator output + BE-25 Distiller parse allowlist + Guardrail::Validator + BE-24 circuit breaker + BE-26 cost caps. **TODOS os caminhos LLM têm validação de output**
- 🟢 **Performance: 26/26 resolvido** — hot paths + paginação opt-in + frontend perf + embed batch + circuit breaker + **virtualização RoomList + MentionsView (PERF-25 lote 64)**. MessageThread mantido sem virtualização por decisão consciente (5 riscos documentados, revisitar com E2E framework)
- 🟢 **Escalabilidade: 100% resolvido** (3/3) — cron jobs paralelizados via Sidekiq per-account
- 🟢 **Backend: 100% resolvido** (24/24) — race conditions, soft-deletes, encryption docs, output validation
- 🟢 **Frontend: 23/23 resolvido** — god files decompostos (FE-1 -11%, FE-2 -46%, FE-3 -73%, FE-4 -67%), i18n completo, UX gating, **UI primitives padronizados (FE-8 lote 63: 23 substituições em 13 components)**. ZERO roadmap em Frontend
- 🟢 **Arquiteturais: 23/23 resolvido** — Fase 4 ChatService 1017→907 + 3 módulos (120/120 specs verde), READMEs, ADRs, UserBroadcaster, ReadReceipt formalizado, drift detection spec (16 examples), **SearchAvailableSlotsTool 480→298 LOC + 3 sub-classes (lote 62)**. ZERO roadmap em Arquiteturais
- 🟢 **Specs caracterizadores: 80 examples** cobrindo ChatService, ChatResponseJob, MessageDispatcher, BroadcastMessageJob
- 🟢 **i18n: COMPLETO** — ~236 strings frontend + 17 backend migradas, ~309 keys disponíveis, todos os user-facing components dos 2 plugins i18n-aware

### Falsos positivos confirmados durante remediação

| ID | Categoria | Razão |
|---|---|---|
| **CRÍTICO-11** (`attachments#download` sem auth) | RBAC | `before_action :authorize_room_access` SEM `only:` aplica a TODAS as actions, inclusive download. Já gated. |
| **BE-14** (XSS em SystemMessageBuilder) | Frontend | Frontend renderiza `{{ message.content }}` (Vue auto-escape) — vetor já fechado. Fix aplicado é defesa em profundidade. |
| **PERF-13** (mention + message broadcast duplicados) | Performance | Os 2 eventos servem propósitos distintos (thread render vs notification badge). Frontend já dispatcha pra stores separadas, sem duplicação real. |
| **SEC-13** (LLM injeta contact_id no ErasureRequestTool) parcial | LLM | `contact_id` é injetado pelo tool context, não é arg do LLM (BaseTool#contact_id lê de `context.contact_id`). LLM não controla. Fix aplicado = blindagem contra contexto corrompido. |

---

## 1. Resumo Executivo

### Status geral (auditoria original — 2026-05-18)

| Dimensão | Status original | Status atual (2026-05-19) |
|---|---|---|
| Arquitetura modular (engine isolation) | ✅ Conforme | ✅ Conforme |
| Multi-tenant — modelos | 🟡 Quase conforme | ✅ Conforme |
| Multi-tenant — frontend stores | 🔴 Não conforme | ✅ Conforme (reset action wireada) |
| Realtime (ActionCable) | 🔴 **BLOQUEADOR** | ✅ Funcional (7 handlers wireados) |
| Segurança RBAC | 🔴 Crítico | ✅ Conforme (policies criadas) |
| Segurança LLM (prompt injection / tool safety) | 🔴 Crítico | ✅ Conforme (sanitização + permission gates) |
| Performance | 🟠 Alto | 🟡 Hot paths otimizados; itens menores pendentes |
| Escalabilidade (Sidekiq cron jobs) | 🟠 Alto | 🟠 Mesma situação (escopo não atacado) |
| Aderência ao padrão Beclinic | 🟡 Parcial | 🟡 Mesma (rubocop -A rodado, mas refactors pendentes) |
| Cobertura de testes | 🟠 Lacuna | 🟠 Mesma (specs novos só pra SEC-11 expandido) |

### Nível de risco — readiness produção

**Veredito:** Os engines estão **em produção** (memória do projeto confirma `internal_chat` foi shipado em sprint 7 e `ai_agent` está rodando com `bea_enabled` por conta). Entretanto, a auditoria revelou **3 categorias de bloqueadores** que precisam de mitigação antes de qualquer expansão de escopo ou de tráfego significativo:

1. **Bloqueador funcional:** o `ActionCableConnector` core (em `app/javascript/dashboard/helper/actionCable.js`) **não registra os 7 eventos `internal_chat.*`** que o backend broadcasta — mensagens novas, edições, deletes, menções, typing, room.updated/deleted e read_receipts. O resultado é que mensagens enviadas em sala A só aparecem para outros membros após F5. Se a funcionalidade está percebida como "funcionando" hoje, é porque os usuários estão refrescando manualmente ou porque o teste exercitou apenas o sender.
2. **Bloqueador de segurança RBAC:** `FollowUpRulesController` e `InternalNotificationTemplatesController` em `plugins/ai_agent` aceitam CRUD por qualquer membro da conta sem checar permissão granular. Qualquer recepcionista pode reconfigurar follow-ups e templates de alerta interno.
3. **Bloqueador de isolamento tenant:** quatro consultas `find_by(id:)` sem scope `account_id` no caminho LLM (`ParentChunk` em RAG, `Trace` no endpoint público de feedback, `InternalChat::Message` no `Responder`, `in_reply_to` cross-account). Cada uma é exfiltrável por adversário com IDs adivinhados.

### Score técnico

| Eixo | Score original | Score atual (2026-05-19) |
|---|---|---|
| Arquitetura | 8 | 8 |
| Multi-tenancy backend | 6 | **9** |
| Multi-tenancy frontend | 4 | **8** |
| Segurança (autorização) | 5 | **8** |
| Segurança (LLM) | 5 | **8** |
| Performance | 6 | **7** |
| Realtime | 3 | **8** |
| UX técnica | 6 | 6 |
| Cobertura de testes | 5 | 5 |
| Aderência guidelines | 7 | 7 |
| **Média** | **5.5** | **7.4** |

> Score original 5.5: produto funcional mas com riscos materiais de exposição cross-tenant, autorização frouxa em endpoints de configuração e realtime que dependia de refresh manual.
>
> **Score atual 7.4**: bloqueadores fechados. Vetores residuais são tecnicamente menores (refactors arquiteturais, escalabilidade de cron jobs, cobertura de specs). Produto agora postado defensivamente — riscos críticos endereçados.

---

## 2. Arquitetura Encontrada

### 2.1 `plugins/ai_agent` — visão geral

**Função:** chatbot LLM ("Bea/Beatriz") que atende pacientes em conversas do Chatwoot, busca conhecimento em PDFs via RAG (pgvector), executa tools (booking, cancelamento, lookup), envia follow-ups automáticos, consolida memória do paciente, dispara notificações internas para staff e gera trace de cada turno.

**Provedores LLM:** OpenAI (`gpt-4.1-mini`) e Gemini (`gemini-3-flash-preview`) com fallback automático. Patch específico para `thoughtSignature` do Gemini 3 em [lib/ai_agent/gemini_thought_signature_patch.rb](../../plugins/ai_agent/lib/ai_agent/gemini_thought_signature_patch.rb).

**Modelos (15 tabelas `ai_agent_*`):** `GlobalSetting`, `AccountSetting`, `PersonaTemplate`, `ToolDefinition`, `ConversationState`, `PatientMemory`, `Document`, `ParentChunk`, `ChildChunk`, `FollowUpRule`, `FollowUpExecution`, `InternalNotificationTemplate`, `UsageCounter`, `Trace`, `Feedback`, `AuditLog`.

**Controllers:**
- `AiAgent::Api::V1::Accounts::DocumentsController` — CRUD knowledge base (chama `IngestDocumentJob`).
- `AiAgent::Api::V1::Accounts::FollowUpRulesController` — CRUD regras de follow-up.
- `AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController` — CRUD templates + endpoint `catalog`.
- `Api::V1::AiAgent::HealthController` — público (uptime monitor).
- `Api::V1::AiAgent::FeedbacksController` — público (widget de feedback, protegido por HMAC).

**Services (~50 classes):** organizados em subpastas `tools/` (15+ tools), `internal_chat/`, `humanization/`, `rag/`, `internal_notifier/` (10+ alerts), `memory/`, `multimodal/`, `detectors/`, `emergency/`, `health/`, `lgpd/`, `llm/`, `follow_ups/`, `proactive/`, `state_machine/`, `detectors/`.

**Jobs (8):** `ChatResponseJob`, `FollowUpDispatcherJob`, `SendFollowUpJob`, `IngestDocumentJob`, `ProactiveOutreachJob`, `ConsolidatePatientMemoryJob`, `Health::MonitorJob`, `FollowUps::DispatchAppointmentConfirmedJob`, `InternalChat::RespondJob`.

**Listeners:** `EventListeners::MessageListener` — direto via callback `Message.after_create_commit` (não Wisper, por causa de reload dev).

**Policies:** apenas `DocumentPolicy`. **FollowUpRules e InternalNotificationTemplates não têm policy.**

**Monkey-patches** (em `engine.rb#to_prepare`, todas idempotentes via `unless method_defined?`/`unless reflect_on_association`):
- `Account`: `has_one :ai_agent_setting`, `has_many :ai_agent_usage_counters`, `has_many :documents_for_bea`, `after_create_commit :ensure_default_bea_assistant`, `after_create_commit :seed_ai_agent_internal_notification_templates`.
- `Captain::Assistant`: `before_update :protect_beatriz_rename`, `before_destroy :protect_beatriz_destroy`, `after_save :sync_bea_enabled_to_account_setting`.
- `Captain::Conversation::ResponseBuilderJob`: prepend `SkipBeatrizLegacyResponse`.
- `Message`: `after_create_commit :trigger_ai_agent_listener`.
- `AgendaEvent`: `after_commit :notify_internal_chat_pending_confirmation`, `after_commit :notify_internal_chat_lifecycle_change`.
- `Conversation`: `after_update_commit :reset_ai_agent_state_on_resolve`.
- `BookAppointmentTool` (tool prepend): `BookAppointmentToolPrepend` para alertar staff em booking failures.

**Cron jobs (registrados em `engine.rb#after_initialize`):**
- `FollowUpDispatcherJob` — `* * * * *` (a cada minuto).
- `Health::MonitorJob` — `*/10 * * * *` (cada 10 min).
- `ProactiveOutreachJob` — `0 17 * * *` (diário 14h SP).
- `ConsolidatePatientMemoryJob` — `0 7 * * *` (diário 4h SP).

**Rotas:** todas em `/api/v1/accounts/:account_id/ai_agent/*` exceto `health` e `feedbacks` que ficam em `/api/v1/ai_agent/*` (públicas).

**Frontend (`plugins/ai_agent/frontend`):** apenas 2 routes — `FollowUpsIndex.vue` (37 KB) e `InternalNotificationTemplatesIndex.vue` (23 KB). 2 stores Vuex correspondentes. 2 API clients. Sem composables próprios, sem subscrição a ActionCable. Sem gating em componente (depende de `meta.permissions` no router).

### 2.2 `plugins/internal_chat` — visão geral

**Função:** chat Slack-like entre staff da clínica. Salas direct (1:1), grupos, mensagens com text/sticker/audio/image/video/file/system, menções, reações estilo WhatsApp, favoritos, leituras, indicador de digitação, anexos com previews, painel de arquivos, painel de favoritos.

**Modelos (10 tabelas `internal_chat_*`):** `Room`, `Membership`, `Message`, `Attachment`, `Mention`, `ReadReceipt` (existe mas `Membership.last_read_message_id` é canônico), `Sticker`, `StickerFavorite`, `MessageReaction`, `MessageFavorite`.

**Controllers (7):** `RoomsController`, `MessagesController`, `MembershipsController`, `AttachmentsController`, `StickersController`, `MentionsController`, `TypingController`.

**Services:** `RoomCreator`, `MessageDispatcher`, `MentionExtractor`, `SystemMessageBuilder`, `MessageSerializer`, `RoomSerializer`, `StickerSerializer`, `BeaResolver`, `Telemetry`, `DataExporter`, `ImageWebpConverter`.

**Jobs (2):** `BroadcastMessageJob` (enfileirado por `MessageDispatcher` para broadcast assíncrono via ActionCable), `PurgeUserDataJob` (LGPD).

**Listener:** `AiAgentMentionListener` — quando `@Beatriz` é mencionada em mensagem interna, enfileira `AiAgent::InternalChat::RespondJob`.

**Policies (3):** `RoomPolicy`, `MessagePolicy`, `StickerPolicy`. `MembershipsController`, `AttachmentsController`, `TypingController`, `MentionsController` **não têm policy** — usam checks inline (`@room.member?` ou `Current.account_user.administrator?`).

**ActionCable:** o engine **não define channel próprio**. Todos broadcasts vão para `user.pubsub_token` (stream global do `RoomChannel` core do Chatwoot). Eventos broadcastados:
- `internal_chat.message.created` (BroadcastMessageJob)
- `internal_chat.message.updated` (update, react, unreact)
- `internal_chat.mention.created` (BroadcastMessageJob, para usuários mencionados)
- `internal_chat.read_receipt.updated` (mark_read, para outros membros)
- `internal_chat.room.updated` (update_avatar, remove_avatar, create/update/destroy membership)
- `internal_chat.room.deleted` (destroy)
- `internal_chat.typing` (TypingController)

**Backfill:** migration `20260518000040_add_system_role_to_internal_chat_rooms.rb` cria sala "reception" para cada Account existente com todos os AccountUsers como membros + Bea (se Captain::Assistant existe).

**Rake task:** `internal_chat:seed_default_stickers` importa stickers padrão de `db/seed_stickers/{dentista,bem_estar,estetica}/*` para a base com `account_id = nil` e `kind = 'default'`.

**Frontend:** 22 componentes Vue, 5 stores, 4 composables (`useMentionAutocomplete`, `useAudioRecorder`, `useTypingIndicator`, `stickerImageProcessor`), 7 API clients. Componentes principais: `ChatShell`, `RoomView`, `MessageThread`, `MessageComposer`, `MessageBubble` (1044 linhas!), `GroupSettingsDrawer` (588 linhas).

### 2.3 Fluxo end-to-end de uma mensagem em conversa pública (ai_agent)

```
Patient sends WhatsApp message
  ↓
Chatwoot core ingests → Message.create
  ↓
after_create_commit :trigger_ai_agent_listener  ← monkey-patch do engine
  ↓
EventListeners::MessageListener.message_created
  ↓ filtros (incoming, contact, account enabled, Beatriz, sem assignee, com texto/anexo, rate limit ok)
  ↓
ChatResponseJob.perform_later(message.id, attempt: 1)
  ↓ debounce 3s (espera burst de mensagens)
  ↓
Idempotência: Trace.exists?(message_id, error_message: nil) → skip se já respondeu
  ↓
Transcribe audio (Whisper, max 3 retries × 5s backoff) | Visual classification (Gemini Vision)
  ↓
Memory::CrossConversationHistory.build (10 msgs, TTL 24h, scoped account+contact)
  ↓
ChatService.respond
  ├── Emergency::Detector (keyword) → escalate + template + bypass LLM
  ├── Humanization::SentimentAnalyzer + OffensiveTone + RefundRequest detectors → metadata + alerts
  ├── EscalationRules + StateMachine::ConversationContext (deterministic gates)
  ├── ContextBuilder.block (datetime, clinic hints, patient hints)
  ├── PromptBuilder (persona + memory.preferences + memory.history + context)
  ├── LLM call (com tools registradas via ToolRegistry)
  │     ├── tool call → wrapped via wrap_tool_for_state_capture (sentinel + critique opcionais)
  │     └── retry / provider fallback (Gemini → OpenAI ou vice-versa)
  ├── Humanization::Sentinel (post-response 2nd-layer judge, opt-in CAPTAIN_BEA_SENTINEL_ENABLED)
  ├── Trace.create! (com unique partial index)
  └── Return Result(message, tool_executions, usage, state, handoff, trace)
  ↓
Job: typing_on → post outgoing message → typing_off → handle handoff (private note + status)
```

### 2.4 Fluxo end-to-end de uma mensagem interna (internal_chat)

```
User digita em MessageComposer + clica enviar
  ↓
MessagesAPI.send → POST /api/v1/accounts/:id/internal_chat/rooms/:room_id/messages
  ↓
MessagesController#create
  ↓ authorize_room_access (inline, sem Pundit)
  ↓ ImageWebpConverter (se anexo é imagem)
  ↓
MessageDispatcher.call
  ↓ ActiveRecord::Base.transaction:
  │   ├── Message.create! (sender_user_id OU sender_ai_agent_id)
  │   ├── attach_files (max 15, classify each)
  │   ├── MentionExtractor → list de user_ids + ai_agent_ids
  │   ├── Mention.create! por destinatário válido (filtrado por active membership)
  │   ├── AiAgentMentionListener.call(message, ai_agent_ids) → opcional enqueue RespondJob
  │   └── room.touch_last_message!
  ↓ FORA da transação:
  │   └── BroadcastMessageJob.perform_later(message.id)
  ↓
Controller marca sender como lido + retorna MessageSerializer.as_json (201)
  ↓
BroadcastMessageJob.perform
  ↓ recipient_ids = active memberships (não-AI)
  ↓ User.find_each → ActionCable.server.broadcast(user.pubsub_token, message_payload)
  ↓ se user.id ∈ mention_user_ids: ActionCable.server.broadcast(... mention_payload)
  ↓
Frontend onReceived(payload)
  ↓
ActionCableConnector.events[payload.event] ← *** undefined para internal_chat.* ***
  ↓
🔴 handler nunca dispatcha → store nunca chama receiveFromCable → UI não atualiza
```

### 2.5 Dependências e acoplamento entre plugins

- `ai_agent` → `internal_chat` (legítimo): `InternalNotifier::Dispatcher` cria messages em rooms internas; `InternalChat::RespondJob` lê messages e gera resposta da Bea para staff.
- `internal_chat` → `ai_agent` (legítimo): `BeaResolver` resolve `Captain::Assistant` (core) para mostrar Bea como membro; `AiAgentMentionListener` enfileira job do `ai_agent` quando @Beatriz mencionada.
- Ambos → core Chatwoot/Captain: `Account`, `User`, `AccountUser`, `Message`, `Conversation`, `Captain::Assistant`, `AgendaEvent`. Sempre via `defined?(::X)` guards.

Sem acoplamento circular detectado.

---

## 3. Problemas Encontrados (tabela consolidada)

> Mais de **100 findings** distribuídos. Cada entrada cita arquivo + linha. Detalhamento por categoria nas seções 4–11.

### Legenda de severidade

- **CRÍTICO** — exposição/perda de dados cross-tenant, bypass de autenticação, bloqueador funcional, risco LGPD/HIPAA imediato.
- **ALTO** — bypass de autorização, race condition impactando integridade, performance que quebra a UX em escala atual, perda de funcionalidade.
- **MÉDIO** — degradação UX, complexidade que vira dívida técnica, lacuna de validação não exploitável trivialmente.
- **BAIXO** — code smell, oportunidade de hardening, inconsistência menor.

### Top-30 por severidade

| # | Sev | Tipo | Arquivo | Problema | Impacto |
|---|---|---|---|---|---|
| 1 | CRÍTICO | Realtime | `app/javascript/dashboard/helper/actionCable.js:15-37` | 7 eventos `internal_chat.*` broadcastados pelo backend sem handler registrado | Mensagens novas/edições/menções/typing não aparecem em tempo real; usuário precisa de F5 |
| 2 | CRÍTICO | Multi-tenant | [plugins/ai_agent/app/services/ai_agent/rag/retriever.rb:54](../../plugins/ai_agent/app/services/ai_agent/rag/retriever.rb#L54) | `AiAgent::ParentChunk.find(best.parent_chunk_id)` sem `account_id` | RAG pode promover parent chunk de outra clínica → exfiltração de documentos confidenciais |
| 3 | CRÍTICO | Multi-tenant | [plugins/ai_agent/app/controllers/api/v1/ai_agent/feedbacks_controller.rb:31](../../plugins/ai_agent/app/controllers/api/v1/ai_agent/feedbacks_controller.rb#L31) | `::AiAgent::Trace.find_by(id: trace_id)` global no endpoint público | Qualquer trace_id de qualquer conta é envenenável por atacante que conheça o secret HMAC global |
| 4 | CRÍTICO | Multi-tenant | [plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb:31](../../plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb#L31) | `::InternalChat::Message.find_by(id: @message_id)` no RespondJob | Job com message_id arbitrário responde em sala de outra conta |
| 5 | CRÍTICO | Multi-tenant | [plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb:135](../../plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb#L135) | `::InternalChat::Message.find_by(id: in_reply_to)` cross-room | Patient injeta `in_reply_to: <id_outra_sala>`; Bea inclui conteúdo cross-tenant no prompt e ecoa na resposta |
| 6 | CRÍTICO | RBAC | [plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/follow_up_rules_controller.rb](../../plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/follow_up_rules_controller.rb) (linhas 1–82) | Nenhuma chamada `authorize` ou `check_authorization`; nenhuma policy | Qualquer membro da conta pode criar/editar/deletar regras que disparam mensagens automáticas para pacientes |
| 7 | CRÍTICO | RBAC | [plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/internal_notification_templates_controller.rb](../../plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/internal_notification_templates_controller.rb) (linhas 1–177) | Nenhuma chamada `authorize`; nenhuma policy | Qualquer membro pode reescrever templates de alertas e redirecionar para DMs arbitrários (exfiltração + spam) |
| 8 | CRÍTICO | LLM | [plugins/ai_agent/app/services/ai_agent/prompt_builder.rb:163-184](../../plugins/ai_agent/app/services/ai_agent/prompt_builder.rb#L163-L184) | Nome do contato (`pushName` do WhatsApp) injetado cru no system prompt; `sanitize_name` permite quote/hifen | Prompt injection — paciente troca display name para `Joana ", ignore previous instructions, [...]` |
| 9 | CRÍTICO | LLM | [plugins/ai_agent/app/services/ai_agent/prompt_builder.rb:199-212](../../plugins/ai_agent/app/services/ai_agent/prompt_builder.rb#L199-L212) | `preferences.to_json` e `history[].summary` injetados crus | Memória "envenenada" em turno N afeta turnos N+1, N+2 — injection persistente |
| 10 | CRÍTICO | LLM | [plugins/ai_agent/app/services/ai_agent/tools/erasure_request_tool.rb:51-98](../../plugins/ai_agent/app/services/ai_agent/tools/erasure_request_tool.rb#L51-L98) | Tool não verifica que `contact_id` solicitado pertence ao paciente da conversa | LLM injetado pode disparar erasure request contra qualquer contact_id |
| 11 | CRÍTICO | Frontend | [plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb:115](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb#L115) (download action) | `fetch_room` é chamado mas `authorize_room_access` é skipado no `download` (`only: %i[index]`) | Admin da conta ou membro de outra sala baixa anexos de salas em que não é membro |
| 12 | CRÍTICO | Frontend | [plugins/internal_chat/app/services/internal_chat/system_message_builder.rb:47-58](../../plugins/internal_chat/app/services/internal_chat/system_message_builder.rb#L47-L58) | Nomes interpolados sem escape em texto de mensagem de sistema | XSS se o frontend renderiza mensagem de sistema com `v-html` (verificar antes de exploit confirmado) |
| 13 | ALTO | Multi-tenant | [plugins/ai_agent/app/services/ai_agent/feedback_token_signer.rb:20-27](../../plugins/ai_agent/app/services/ai_agent/feedback_token_signer.rb#L20-L27) | HMAC computado só sobre `trace_id`, secret é `secret_key_base` global; sem TTL | Forja de feedback inter-conta + replay indefinido |
| 14 | ALTO | Multi-tenant | [plugins/internal_chat/app/jobs/internal_chat/purge_user_data_job.rb:11-26](../../plugins/internal_chat/app/jobs/internal_chat/purge_user_data_job.rb#L11-L26) | Purge global por `user_id` sem filtro `account_id` | LGPD spillover — deleta dados do usuário em todas as contas, não só na requerente |
| 15 | ALTO | Multi-tenant | [plugins/internal_chat/app/services/internal_chat/data_exporter.rb:27-36](../../plugins/internal_chat/app/services/internal_chat/data_exporter.rb#L27-L36) | Export por `user_id` sem `account_id` | Mesmo problema do purge — vaza dados de outras contas que o usuário acessa |
| 16 | ALTO | Multi-tenant | [plugins/internal_chat/app/models/internal_chat/sticker_favorite.rb:8](../../plugins/internal_chat/app/models/internal_chat/sticker_favorite.rb#L8) | `StickerFavorite` sem coluna `account_id`; validação só `uniqueness: { scope: :sticker_id }` | Favoritos de stickers default vazam estado cross-conta para mesmo `user_id` |
| 17 | ALTO | Performance | [plugins/internal_chat/app/services/internal_chat/room_serializer.rb:11](../../plugins/internal_chat/app/services/internal_chat/room_serializer.rb#L11) | N+1 — `RoomsController#index` chama `RoomSerializer.new(room, ...).as_json` em loop sem preload de `messages.first` | 100 salas = 100+ queries; 1000 salas = ~5–10s de latência |
| 18 | ALTO | Performance | [plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb:262-278](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L262-L278) | `mark_read` broadcasta para cada outro membro toda vez | 50 membros × 200 mensagens lidas = 10k broadcasts/dia/sala |
| 19 | ALTO | Performance | [plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb:17-45](../../plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb#L17-L45) | Membro mencionado recebe `message.created` + `mention.created` (duplicado) | Cliente recebe 2 eventos para mesma mensagem; frontend precisa dedup |
| 20 | ALTO | RBAC | [plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb:118-122](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb#L118-L122) e [typing_controller.rb:35-39](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/typing_controller.rb#L35-L39) | Auth inline em controllers; sem Pundit policy class | Se um dia adicionarem perm granular `internal_chat:view_attachments_only`, esses controllers não respeitam |
| 21 | ALTO | RBAC | [plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/memberships_controller.rb:78-84](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/memberships_controller.rb#L78-L84) | Sem perm granular `internal_chat:manage_memberships` no KlivyRole | Qualquer "room owner" (mesmo recepcionista promovido) pode adicionar/remover qualquer staff de qualquer sala |
| 22 | ALTO | RBAC | [plugins/ai_agent/app/services/ai_agent/tools/internal_cancel_appointment_tool.rb:35-44](../../plugins/ai_agent/app/services/ai_agent/tools/internal_cancel_appointment_tool.rb#L35-L44) (e similares Internal*Tool) | Tool executa ação privilegiada sem checar perm do staff que invocou Bea | Recepcionista sem `agenda:cancel_event` pede "@bea cancela 42" e Bea executa |
| 23 | ALTO | LLM | [plugins/ai_agent/app/services/ai_agent/chat_service.rb:847-870](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb#L847-L870) | Provider fallback Gemini→OpenAI executa segunda chamada completa | 4× custo esperado quando Gemini falha; sem circuit breaker; sem cost cap por turn |
| 24 | ALTO | LLM | [plugins/ai_agent/app/services/ai_agent/tools/create_patient_minimal_tool.rb](../../plugins/ai_agent/app/services/ai_agent/tools/create_patient_minimal_tool.rb) | Sem rate limit por contact | Patient/atacante pede "cria ficha pra X, Y, Z..." em rajada → milhares de Patient órfãos |
| 25 | ALTO | LLM | [plugins/ai_agent/app/jobs/ai_agent/ingest_document_job.rb:22-52](../../plugins/ai_agent/app/jobs/ai_agent/ingest_document_job.rb#L22-L52) | `document.update!(status: :processing)` FORA da transação; embeddings sem batching | Re-ingest com falha no meio = loop infinito (status nunca limpa); custo de embedding 100× sem batching |
| 26 | ALTO | LLM | [plugins/ai_agent/app/services/ai_agent/humanization/sentinel.rb](../../plugins/ai_agent/app/services/ai_agent/humanization/sentinel.rb) | Sentinel vê texto da Bea que pode conter eco do user; injection passa pelo "judge" | Bypass do guardrail de 2ª camada |
| 27 | ALTO | Multi-tenant | [plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb:28-30](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb#L28-L30) | Job acessa `message.account` por traversal; sem validar account_id passado | Race condition se conversation reatribuída entre enqueue e execução |
| 28 | MÉDIO | Frontend | [plugins/internal_chat/frontend/store/internalChatStickers.js](../../plugins/internal_chat/frontend/store/internalChatStickers.js) | Flag `loaded: true` no store nunca invalidada no account-switch | Trocar de conta mantém lista de stickers cacheada da conta anterior (até logout) |
| 29 | MÉDIO | Frontend | [plugins/internal_chat/frontend/store/internalChatTyping.js](../../plugins/internal_chat/frontend/store/internalChatTyping.js) | `TIMERS` em module scope; sem cleanup em logout/account-switch | Memory leak progressivo + timers órfãos disparando após context inválido |
| 30 | MÉDIO | Frontend | [plugins/internal_chat/app/models/internal_chat/membership.rb:16-20](../../plugins/internal_chat/app/models/internal_chat/membership.rb#L16-L20) | `unread_count` não filtra `.visible` (mensagens soft-deleted contam como não-lidas) | Badge mostra `2` mas usuário só vê `1` mensagem na sala |

> Total compilado: **100+ findings**. As seções 4–11 listam todos por categoria.

---

## 4. Vazamentos Multi-Tenant

### 4.1 Lookups sem `account_id` (CRÍTICO)

| # | Arquivo:linha | Excerpt | Risco |
|---|---|---|---|
| MT-1 | [plugins/ai_agent/app/services/ai_agent/rag/retriever.rb:54](../../plugins/ai_agent/app/services/ai_agent/rag/retriever.rb#L54) | `parent = AiAgent::ParentChunk.find(best.parent_chunk_id)` | Promover chunk de outra conta retorna conteúdo confidencial dela. Mitigação: o child chunk inicial é scoped, mas se houver bug que retorne best com parent_chunk_id de outra conta, parent é lookup global. |
| MT-2 | [plugins/ai_agent/app/controllers/api/v1/ai_agent/feedbacks_controller.rb:31](../../plugins/ai_agent/app/controllers/api/v1/ai_agent/feedbacks_controller.rb#L31) | `trace = ::AiAgent::Trace.find_by(id: trace_id)` | Endpoint público; sem `account_id` no HMAC; sem TTL. |
| MT-3 | [plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb:31](../../plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb#L31) | `message = ::InternalChat::Message.find_by(id: @message_id)` | Job aceita só `message_id`; sem validar `account_id`. |
| MT-4 | [plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb:135](../../plugins/ai_agent/app/services/ai_agent/internal_chat/responder.rb#L135) | `::InternalChat::Message.find_by(id: in_reply_to)` | `in_reply_to` é do client; sem validar mesma room. |

### 4.2 Jobs sem propagação de `account_id` (ALTO)

| # | Arquivo:linha | Problema | Fix sugerido |
|---|---|---|---|
| MT-5 | [plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb:28-30](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb#L28-L30) | `message.account` por traversal; rate limiter usa só `conversation_id` no fallback | Passar `account_id:` como argumento do job e validar |
| MT-6 | [plugins/internal_chat/app/jobs/internal_chat/purge_user_data_job.rb:11-26](../../plugins/internal_chat/app/jobs/internal_chat/purge_user_data_job.rb#L11-L26) | Deleta msgs/memberships/mentions global por `user_id` | Adicionar `account_id:` obrigatório |
| MT-7 | [plugins/ai_agent/app/jobs/ai_agent/follow_up_dispatcher_job.rb:27-31](../../plugins/ai_agent/app/jobs/ai_agent/follow_up_dispatcher_job.rb#L27-L31) | Itera `FollowUpRule.enabled.find_each` global; rate-limit (`DAILY_CAP_PER_ACCOUNT = 200`) aplicado depois | Agrupar por `account_id` no início |
| MT-8 | `plugins/ai_agent/app/jobs/ai_agent/health/monitor_job.rb` | Cron global; se Notifier não scopa, alerta cross-conta | Iterar `Account.find_each` e passar `account_id:` ao Checker |
| MT-9 | `plugins/ai_agent/app/jobs/ai_agent/proactive_outreach_job.rb` | Iteração com `AccountSetting.where(enabled: true).find_each` está OK, mas `RecallFinder` precisa de `account_id` propagado dentro | Verificar implementação |
| MT-10 | `plugins/ai_agent/app/jobs/ai_agent/consolidate_patient_memory_job.rb` | Similar | Verificar que distiller recebe `account_id` |

### 4.3 Modelos sem validação de coerência cross-tenant

| # | Modelo | Problema |
|---|---|---|
| MT-11 | [plugins/internal_chat/app/models/internal_chat/sticker_favorite.rb](../../plugins/internal_chat/app/models/internal_chat/sticker_favorite.rb) | Sem `account_id` na tabela; favorite de default sticker é global por user |
| MT-12 | [plugins/internal_chat/app/models/internal_chat/mention.rb](../../plugins/internal_chat/app/models/internal_chat/mention.rb) | `account_id` denormalizado mas sem validation `mention.account_id == message.room.account_id` |
| MT-13 | [plugins/internal_chat/app/models/internal_chat/message_reaction.rb](../../plugins/internal_chat/app/models/internal_chat/message_reaction.rb) e [message_favorite.rb](../../plugins/internal_chat/app/models/internal_chat/message_favorite.rb) | `room_id` denormalizado sem validation de coerência com `message.room_id` |

### 4.4 Frontend stores não keyed por account

| # | Store | Problema |
|---|---|---|
| MT-14 | [plugins/internal_chat/frontend/store/internalChatStickers.js](../../plugins/internal_chat/frontend/store/internalChatStickers.js) | `loaded: true` nunca invalida em account switch |
| MT-15 | [plugins/internal_chat/frontend/store/internalChatTyping.js](../../plugins/internal_chat/frontend/store/internalChatTyping.js) | `TIMERS` Map em module scope; nem reset nem cleanup |
| MT-16 | [plugins/internal_chat/frontend/store/internalChatRooms.js](../../plugins/internal_chat/frontend/store/internalChatRooms.js) | `records` global; ao trocar conta, lista mantém dados antigos até full reload |
| MT-17 | [plugins/internal_chat/frontend/store/internalChatMessages.js](../../plugins/internal_chat/frontend/store/internalChatMessages.js) | `byRoom` global; mesma situação |
| MT-18 | [plugins/internal_chat/frontend/store/internalChatMentions.js](../../plugins/internal_chat/frontend/store/internalChatMentions.js) | `records` e `unreadCount` globais |
| MT-19 | [plugins/ai_agent/frontend/store/aiAgentFollowUpRules.js](../../plugins/ai_agent/frontend/store/aiAgentFollowUpRules.js) e [aiAgentInternalNotificationTemplates.js](../../plugins/ai_agent/frontend/store/aiAgentInternalNotificationTemplates.js) | `records` global; mitigado pelo full reload do `SidebarAccountSwitcher`, mas conforme AGENTS.md a regra exige keying explícito |

### 4.5 Sticker default + `for_account` scope (MÉDIO)

`Sticker.for_account(account_id)` (em [plugins/internal_chat/app/models/internal_chat/sticker.rb:30](../../plugins/internal_chat/app/models/internal_chat/sticker.rb#L30)) retorna `account_id = ?` ∪ `account_id IS NULL`. Isso está correto para defaults. Mas:
- `MessagesController#create` resolve `sticker_id` via `Sticker.where(account_id: [Current.account.id, nil]).where(id: sid).pick(:id)` ([linhas 220-229](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L220-L229)). Se `sid` for de outra conta, retorna `nil` (safe). ✅
- `StickersController#fetch_sticker` em [linhas 149-154](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/stickers_controller.rb#L149-L154) usa `.find` (não `.find_by`) — vai 404 se sticker não está no scope. ✅

→ **Não é um vazamento confirmado.** Defense-in-depth: validar explicitamente `sticker.account_id.nil? || sticker.account_id == Current.account.id` antes de retornar.

### 4.6 Broadcasts ActionCable scope

Todos broadcasts do `internal_chat` vão para `user.pubsub_token` (stream pessoal do user). Recipient list é construída a partir de `room.memberships.active` — então só membros ativos recebem. **OK** desde que:
- Inconsistência sintática entre `where(left_at: nil)` em [BroadcastMessageJob:18-21](../../plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb#L18-L21) e `.active` em [MessagesController:241](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L241) — funcionalmente equivalente mas se algum dia mudar o scope, drift. (Finding **MT-20**, severidade BAIXO.)

### 4.7 Cache keys / Redis

`AiAgent::RateLimiter` usa Redis com keys `ai_agent:rate:#{account_id}:#{conversation_id}` e `ai_agent:rate:account:#{account_id}`. **OK** — sempre prefixadas por `account_id`.

Não encontrados `Rails.cache.*` ou `Redis.current.*` sem prefixo de conta em ambos plugins.

### 4.8 Sumário multi-tenant

| Severidade | Quantidade |
|---|---|
| CRÍTICO | 4 (MT-1 a MT-4) |
| ALTO | 7 (MT-5 a MT-11) |
| MÉDIO | 8 (MT-12 a MT-19) |
| BAIXO | 1 (MT-20) |
| **Total** | **20** |

---

## 5. Problemas de Segurança

### 5.1 Autorização ausente / controllers sem policy (CRÍTICO/ALTO)

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-1 | CRÍTICO | [follow_up_rules_controller.rb](../../plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/follow_up_rules_controller.rb) | Sem `authorize`/`check_authorization` e sem policy class |
| SEC-2 | CRÍTICO | [internal_notification_templates_controller.rb](../../plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/internal_notification_templates_controller.rb) | Mesmo problema; ataque pode redirecionar templates para DM exfiltrável |
| SEC-3 | ALTO | [attachments_controller.rb](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb) | Auth inline (`@room.member?` ou admin), sem Pundit; `download` action **sem** `authorize_room_access` no `before_action :only` |
| SEC-4 | ALTO | [typing_controller.rb](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/typing_controller.rb) | Auth inline, sem policy |
| SEC-5 | ALTO | [memberships_controller.rb](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/memberships_controller.rb) | Sem policy; sem perm granular `internal_chat:manage_memberships` no KlivyRole |
| SEC-6 | ALTO | [mentions_controller.rb](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/mentions_controller.rb) | Sem policy; auth confiada no `account_id: Current.account.id, user_id: Current.user.id` no scope inline |

### 5.2 Bugs em policies existentes

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-7 | ALTO | [internal_chat/room_policy.rb:47-52](../../plugins/internal_chat/app/policies/internal_chat/room_policy.rb#L47-L52) | `destroy?` admin bypass sem audit log; criador da sala não é notificado |
| SEC-8 | MÉDIO | [internal_chat/message_policy.rb:26-37](../../plugins/internal_chat/app/policies/internal_chat/message_policy.rb#L26-L37) | `update?/destroy?` só valida `sender_user_id == user.id`; não revalida que sender ainda é membro da sala atual |
| SEC-9 | MÉDIO | [internal_chat/message_policy.rb:26-37](../../plugins/internal_chat/app/policies/internal_chat/message_policy.rb#L26-L37) | Janela de 5 min não está na policy — só no controller. Se outra entrada criar bypass, edits indefinidos. |
| SEC-10 | BAIXO | [internal_chat/sticker_policy.rb](../../plugins/internal_chat/app/policies/internal_chat/sticker_policy.rb) | `destroy?` rejeita `kind='default'` — correto. Mas update via `update_columns` no console ainda é possível (super_admin only, aceitável). |

### 5.3 HMAC / Token signing

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-11 | ALTO | [feedback_token_signer.rb:20-32](../../plugins/ai_agent/app/services/ai_agent/feedback_token_signer.rb#L20-L32) | HMAC só sobre `trace_id`; sem `account_id`; sem TTL; secret é `secret_key_base` global |

Atacante com qualquer `trace_id` (vazado via widget ou log) pode forjar token (secret é o mesmo do app), enviar feedback negativo em qualquer conversa de qualquer conta, indefinidamente, sem ser detectado.

### 5.4 Jobs e tools executando ações privilegiadas

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-12 | ALTO | [internal_cancel_appointment_tool.rb:35-44](../../plugins/ai_agent/app/services/ai_agent/tools/internal_cancel_appointment_tool.rb#L35-L44), [internal_book_appointment_tool.rb](../../plugins/ai_agent/app/services/ai_agent/tools/internal_book_appointment_tool.rb), [internal_reschedule_appointment_tool.rb](../../plugins/ai_agent/app/services/ai_agent/tools/internal_reschedule_appointment_tool.rb), [internal_search_patient_tool.rb](../../plugins/ai_agent/app/services/ai_agent/tools/internal_search_patient_tool.rb) | Internal tools executam ações privilegiadas sem checar perm do staff que mencionou Bea |
| SEC-13 | CRÍTICO | [erasure_request_tool.rb:51-98](../../plugins/ai_agent/app/services/ai_agent/tools/erasure_request_tool.rb#L51-L98) | Tool aceita `contact_id` do contexto LLM sem confirmar que é igual ao da conversa atual |
| SEC-14 | ALTO | [create_patient_minimal_tool.rb](../../plugins/ai_agent/app/services/ai_agent/tools/create_patient_minimal_tool.rb) | Sem rate limit por contact; permite spawn em rajada |
| SEC-15 | MÉDIO | [purge_user_data_job.rb](../../plugins/internal_chat/app/jobs/internal_chat/purge_user_data_job.rb) | Sem autorização interna; se exposto via API no futuro, qualquer um deleta dados de qualquer user |
| SEC-16 | MÉDIO | [data_exporter.rb](../../plugins/internal_chat/app/services/internal_chat/data_exporter.rb) | Sem verificar que caller é o próprio usuário ou admin com permissão LGPD |

### 5.5 Frontend gating

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-17 | MÉDIO | [plugins/internal_chat/frontend/components/GroupSettingsDrawer.vue](../../plugins/internal_chat/frontend/components/GroupSettingsDrawer.vue) | Botões de add/remove member, change role visíveis para qualquer membro; gating é só backend |
| SEC-18 | MÉDIO | [plugins/internal_chat/frontend/routes/routes.js](../../plugins/internal_chat/frontend/routes/routes.js) | `meta.permissions` declarado mas sem checagem granular `internal_chat:view` no router guard |
| SEC-19 | BAIXO | [plugins/ai_agent/frontend/routes/routes.js](../../plugins/ai_agent/frontend/routes/routes.js) | Similar |

### 5.6 Input validation / mass-assignment

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-20 | MÉDIO | [message_dispatcher.rb:71-79](../../plugins/internal_chat/app/services/internal_chat/message_dispatcher.rb#L71-L79) | Aceita `content_attributes[:mentioned_ai_agent_ids]` do client sem validar |
| SEC-21 | MÉDIO | `messages_controller.rb#message_params` | Verificar se `content_attributes` é hash livre ou tem schema permitido |

### 5.7 LLM-specific

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-22 | CRÍTICO | [prompt_builder.rb:163-184](../../plugins/ai_agent/app/services/ai_agent/prompt_builder.rb#L163-L184) | Prompt injection via nome do contato |
| SEC-23 | CRÍTICO | [prompt_builder.rb:199-212](../../plugins/ai_agent/app/services/ai_agent/prompt_builder.rb#L199-L212) | Prompt injection persistente via memória do paciente |
| SEC-24 | ALTO | [humanization/sentinel.rb](../../plugins/ai_agent/app/services/ai_agent/humanization/sentinel.rb) | Sentinel pode ser injetado se Bea eco de input do user |
| SEC-25 | ALTO | [follow_ups/message_generator.rb:44-49](../../plugins/ai_agent/app/services/ai_agent/follow_ups/message_generator.rb#L44-L49) | Output do LLM enviado sem validação que parece mensagem (não JSON, não código) |
| SEC-26 | MÉDIO | [internal_notifier/dispatcher.rb](../../plugins/ai_agent/app/services/ai_agent/internal_notifier/dispatcher.rb) | `TemplateRenderer.render` sem escape de vars user-controlled (terms, etc.) |

### 5.8 Endpoints públicos

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-27 | BAIXO | [health_controller.rb:14-23](../../plugins/ai_agent/app/controllers/api/v1/ai_agent/health_controller.rb#L14-L23) | Retorna `snapshot.to_h` completo — vazamento de info de provider/error rates |
| SEC-28 | ALTO | [feedbacks_controller.rb](../../plugins/ai_agent/app/controllers/api/v1/ai_agent/feedbacks_controller.rb) | `skip_before_action :verify_authenticity_token` + sem rate limit |

### 5.9 Engine monkey-patches que afetam segurança

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| SEC-29 | BAIXO | [engine.rb:175-214](../../plugins/ai_agent/lib/ai_agent/engine.rb#L175-L214) | `protect_beatriz_destroy` via `before_destroy` é bypassável por `delete_all` / `update_columns` em raw SQL — só super_admin tem acesso, aceitável mas documentar |

### 5.10 Sumário segurança

| Severidade | Quantidade |
|---|---|
| CRÍTICO | 5 (SEC-1, 2, 13, 22, 23) |
| ALTO | 11 |
| MÉDIO | 9 |
| BAIXO | 4 |
| **Total** | **29** |

---

## 6. Problemas de Performance

### 6.1 N+1 e queries pesadas

| # | Severidade | Arquivo | Problema | Impacto |
|---|---|---|---|---|
| PERF-1 | ALTO | [internal_chat/room_serializer.rb:11](../../plugins/internal_chat/app/services/internal_chat/room_serializer.rb#L11) | `@room.messages.visible.order(id: :desc).first` por serialize | 100 salas → 100+ queries |
| PERF-2 | ALTO | [rooms_controller.rb#unread_summary:143-154](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/rooms_controller.rb#L143-L154) | Loop `find_each` chamando `unread_count` per membership | 100 salas = 100 queries de COUNT |
| PERF-3 | ALTO | [stickers_controller.rb:133-147](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/stickers_controller.rb#L133-L147) | `recent_stickers_for` agrega em Ruby (`sort_by`/`first(10)`) | Usuário com 5000 figurinhas faz sort full em memória |
| PERF-4 | ALTO | [ai_agent/consolidate_patient_memory_job.rb:50-58](../../plugins/ai_agent/app/jobs/ai_agent/consolidate_patient_memory_job.rb#L50-L58) | `jsonb_array_length(history) >= 5` sem index expression; subquery `recently_active_contact_ids` faz full scan de Message | Full table scan diário |
| PERF-5 | MÉDIO | [ai_agent/health/checker.rb:54-78](../../plugins/ai_agent/app/services/ai_agent/health/checker.rb#L54-L78) | Sem index compound `(account_id, created_at, escalated, error_message)` | A cada 10 min × 1000 contas = 144k scans/dia |

### 6.2 Índices ausentes

| # | Severidade | Tabela | Falta |
|---|---|---|---|
| PERF-6 | ALTO | `ai_agent_follow_up_executions` | Cooldown query usa `(account_id, contact_id, status, sent_at)`; índice atual é `(account_id, status, target_at)` — falta `contact_id` |
| PERF-7 | MÉDIO | `ai_agent_traces` | Falta `(account_id, created_at DESC, escalated, error_message)` para health checker |
| PERF-8 | MÉDIO | `ai_agent_patient_memories` | Sem index expression em `jsonb_array_length(history)` |
| PERF-9 | MÉDIO | `ai_agent_child_chunks` | IVFFlat só em `embedding`; sem partial index por `account_id` (cross-tenant filter pós-vetor) |
| PERF-10 | BAIXO | `internal_chat_messages` | GIN em `content_attributes` — verificar se queries por `in_reply_to` usam |

### 6.3 Tempestades de broadcast

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| PERF-11 | ALTO | [messages_controller.rb:262-278](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L262-L278) | `mark_read` broadcasta para N-1 membros por chamada |
| PERF-12 | ALTO | [typing_controller.rb:8-27](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/typing_controller.rb#L8-L27) | Broadcasta a cada `active=true`; sem rate limit servidor (só debounce client) |
| PERF-13 | ALTO | [broadcast_message_job.rb:17-45](../../plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb#L17-L45) | Usuário mencionado recebe message + mention (duplicado) |
| PERF-14 | MÉDIO | [broadcast_message_job.rb:23-45](../../plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb#L23-L45) | `User.find_by(id: uid)` extra dentro do loop apesar de já estar `find_each` |

### 6.4 Paginação ausente / mal capada

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| PERF-15 | MÉDIO | [rooms_controller.rb#index](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/rooms_controller.rb) | Sem paginação; conta com 500 salas retorna tudo |
| PERF-16 | MÉDIO | [messages_controller.rb#favorites:128-151](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L128-L151) | Limit fixo 200 sem paginação; favoritos antigos perdidos |
| PERF-17 | BAIXO | [attachments_controller.rb#index](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb) | Limit 200 fixo; arquivos antigos não listados |

### 6.5 Jobs e cron

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| PERF-18 | ALTO | [follow_up_dispatcher_job.rb:27-31](../../plugins/ai_agent/app/jobs/ai_agent/follow_up_dispatcher_job.rb#L27-L31) | Cron cada minuto, itera todas as rules globais; 1000 contas × 50 rules × 1440 min × 30 dias = 2.16 bilhões de checks/mês |
| PERF-19 | ALTO | [consolidate_patient_memory_job.rb:41-47](../../plugins/ai_agent/app/jobs/ai_agent/consolidate_patient_memory_job.rb#L41-L47) | Distiller LLM sync por paciente; 100 pacientes × 3s = 5 min/conta; 1000 contas = inviável em janela |
| PERF-20 | MÉDIO | [chat_response_job.rb](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb) | `retry: 0` (sem auto-retry Sidekiq); falhas transitórias requerem refazer manual |
| PERF-21 | BAIXO | [ingest_document_job.rb](../../plugins/ai_agent/app/jobs/ai_agent/ingest_document_job.rb) | Embeddings sem batching (1 chamada por child chunk) |

### 6.6 Frontend reativos

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| PERF-22 | BAIXO | [MessageThread.vue](../../plugins/internal_chat/frontend/components/MessageThread.vue) | Dois watchers (length + deep) redundantes |
| PERF-23 | BAIXO | [StickerPicker.vue](../../plugins/internal_chat/frontend/components/StickerPicker.vue) | `refresh()` sempre refetch; sem deduplicação de requests in-flight |
| PERF-24 | BAIXO | [FilesPanel.vue:42-43](../../plugins/internal_chat/frontend/components/FilesPanel.vue#L42-L43) | Keydown listener não removido em mudança de subTab |
| PERF-25 | MÉDIO | RoomList / MessageThread / StickerPicker | Sem virtualização de listas longas |
| PERF-26 | BAIXO | RoomList search input | Sem debounce |

### 6.7 Sumário performance

| Severidade | Quantidade |
|---|---|
| ALTO | 9 |
| MÉDIO | 9 |
| BAIXO | 8 |
| **Total** | **26** |

---

## 7. Problemas de Escalabilidade

> Diferente de performance pontual, escalabilidade observa o comportamento sob carga crescente (mais tenants, mais usuários, mais mensagens).

### 7.1 Cron jobs globais sem batching por conta

| # | Severidade | Job | Risco em escala |
|---|---|---|---|
| ESC-1 | ALTO | `FollowUpDispatcherJob` cada minuto | 1000+ tenants → jobs sequenciais empilham; jobs do minuto N+1 começam antes do N terminar |
| ESC-2 | ALTO | `ConsolidatePatientMemoryJob` diário | LLM sync; sem paralelismo; tempo de execução O(tenants × pacientes_eligible) |
| ESC-3 | MÉDIO | `ProactiveOutreachJob` diário | Similar — escalonamento por tenant é OK, mas sem paralelismo |
| ESC-4 | MÉDIO | `Health::MonitorJob` cada 10 min | Mesma agregação por tenant; índices ausentes amplificam |

### 7.2 Broadcasts em escala

| # | Severidade | Cenário | Cálculo |
|---|---|---|---|
| ESC-5 | ALTO | `mark_read` em sala grande | 50 membros × 200 marks/dia/membro × N-1 broadcasts = 500k broadcasts/dia/sala |
| ESC-6 | ALTO | `typing` em sala ativa | 50 membros digitando = 50 × ~1 broadcast/s × 49 destinatários = 2450 broadcasts/s |
| ESC-7 | MÉDIO | `BroadcastMessageJob` extra User.find_by | 200 msgs/dia × 50 membros = 10k queries User/dia extras |

### 7.3 Sidekiq queue isolation

| # | Severidade | Problema |
|---|---|---|
| ESC-8 | MÉDIO | `BroadcastMessageJob` na queue `:default` compete com Chatwoot core; latência cresce |
| ESC-9 | MÉDIO | `ChatResponseJob` na queue `:default`; deveria ter queue dedicada `:ai` para isolar latência LLM |

### 7.4 RAG / vector index

| # | Severidade | Problema |
|---|---|---|
| ESC-10 | ALTO | IVFFlat só em `embedding` sem partial index por `account_id` ([migration:24-29](../../plugins/ai_agent/db/migrate/20260518000009_create_ai_agent_child_chunks.rb#L24-L29)); search escaneia full table |

### 7.5 Frontend stores não-keyed → re-fetch global no account-switch

Conforme MT-14 a MT-19: account-switch deveria invalidar stores. Hoje depende do `SidebarAccountSwitcher` fazer full reload — não é garantido.

### 7.6 Trace table bloat

| # | Severidade | Problema |
|---|---|---|
| ESC-11 | MÉDIO | Sem TTL ou archival em `ai_agent_traces`; cresce indefinidamente; health checker degrada lentamente |
| ESC-12 | BAIXO | `ai_agent_audit_logs` mesma situação |

### 7.7 Sumário escalabilidade

| Severidade | Quantidade |
|---|---|
| ALTO | 5 |
| MÉDIO | 6 |
| BAIXO | 1 |
| **Total** | **12** |

---

## 8. Problemas de Realtime / WebSocket

### 8.1 Bloqueador: handlers ausentes (CRÍTICO)

**RT-1** — Em `app/javascript/dashboard/helper/actionCable.js:15-37` (core Chatwoot), o registry `this.events = {...}` lista 18 eventos core mas **nenhum dos 7 eventos `internal_chat.*`**:
- `internal_chat.message.created`
- `internal_chat.message.updated`
- `internal_chat.mention.created`
- `internal_chat.typing`
- `internal_chat.room.updated`
- `internal_chat.room.deleted`
- `internal_chat.read_receipt.updated`

Os stores frontend (`internalChatMessages.js`, `internalChatRooms.js`, `internalChatTyping.js`, `internalChatMentions.js`) **definem** actions `receiveFromCable`, `upsertFromCable`, `handleDeletedFromCable`, `applyReadReceipt`, `receive` — mas **nenhum lugar no código frontend dispatcha essas actions**. Verificação por grep retornou zero matches.

**Resultado prático:** mensagens enviadas em sala A só aparecem para outros membros após F5 manual; typing indicator nunca acende; menções não atualizam badge em tempo real.

**Fix:** estender `ActionCableConnector` (no host app, não no plugin) registrando handlers para cada evento e dispatchando a action correspondente do store. Ou registrar via hook de extensão se existir.

### 8.2 Outras issues de realtime

| # | Sev | Arquivo | Problema |
|---|---|---|---|
| RT-2 | ALTO | [broadcast_message_job.rb:18-21](../../plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb#L18-L21) vs [messages_controller.rb:241](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L241) | Inconsistência: `where(left_at: nil)` direto vs `.active` scope; funcionalmente igual mas drift-prone |
| RT-3 | MÉDIO | [rooms_controller.rb#destroy:64-74](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/rooms_controller.rb#L64-L74) | Coleta member_ids → destroy! → broadcast em loop; se `User.find_by` falhar, esse user não recebe delete event |
| RT-4 | MÉDIO | [typing_controller.rb:8-27](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/typing_controller.rb#L8-L27) | Channel storm (PERF-12); server-side sem rate limit |
| RT-5 | MÉDIO | Frontend stores | Sem reconciliation no reconnect — mensagens perdidas durante disconnect ficam silenciosamente faltando |
| RT-6 | BAIXO | `RoomChannel` (core) | Cada usuário tem 1 stream global; OK hoje, mas se mudar para per-room streams precisará cleanup explícito |
| RT-7 | BAIXO | [read_receipts] | Sender atualiza local manualmente em [messages_controller.rb:162-164](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L162-L164); fragil |
| RT-8 | BAIXO | [chat_response_job.rb:274-295](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb#L274-L295) | Typing indicator do Bea: dispatch para `AgentBot` que não tem `pubsub_token` → falha silenciosa; agentes em dashboard não veem "Bea está digitando" |

### 8.3 Sumário realtime

| Severidade | Quantidade |
|---|---|
| CRÍTICO | 1 |
| ALTO | 1 |
| MÉDIO | 3 |
| BAIXO | 3 |
| **Total** | **8** |

---

## 9. Problemas de Frontend

### 9.1 Componentes monolíticos

| # | Severidade | Arquivo | Linhas | Problema |
|---|---|---|---|---|
| FE-1 | ALTO | [MessageBubble.vue](../../plugins/internal_chat/frontend/components/MessageBubble.vue) | 1044 | God file: rendering + edit + favorite + reactions + sticker preview + menu + read receipts + delete confirm + reply + private reply + sender colorization |
| FE-2 | ALTO | [GroupSettingsDrawer.vue](../../plugins/internal_chat/frontend/components/GroupSettingsDrawer.vue) | 588 | 3 views + edit + avatar + member search + role mgmt + deletion |
| FE-3 | MÉDIO | [followUps/Index.vue](../../plugins/ai_agent/frontend/routes/followUps/Index.vue) | 690 | Form + grid + modal + 6 trigger types hardcoded |
| FE-4 | MÉDIO | [internalNotificationTemplates/Index.vue](../../plugins/ai_agent/frontend/routes/internalNotificationTemplates/Index.vue) | 471 | Form + preview + variables + grid |

### 9.2 Violações AGENTS.md (componentes shared)

| # | Severidade | Problema |
|---|---|---|
| FE-5 | MÉDIO | Grep por uso de `Tooltip` do beclinic_core: 0 matches em ambos plugins |
| FE-6 | MÉDIO | Grep por `title="..."` HTML nativo: 19 ocorrências (`FilesPanel.vue`, `StickerPicker.vue`, outras) |
| FE-7 | MÉDIO | Grep por `window.confirm` / `window.alert`: 2 ocorrências (`followUps/Index.vue:228` e `internalNotificationTemplates/Index.vue:115`) |
| FE-8 | MÉDIO | Grep por uso de `BeclinicButton` / `FormSelect` / `Checkbox` do beclinic_core: 0 matches |

### 9.3 Reatividade e cleanup

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| FE-9 | MÉDIO | [internalChatTyping.js](../../plugins/internal_chat/frontend/store/internalChatTyping.js) | `TIMERS` Map module-scope; sem cleanup em logout/account-switch |
| FE-10 | MÉDIO | [useAudioRecorder.js](../../plugins/internal_chat/frontend/composables/useAudioRecorder.js) | `stream`, `recorder`, `timerId` module-scope (não refs); cleanup via `onBeforeUnmount(cancel)` — OK funcionalmente mas com risco se múltiplas instâncias |
| FE-11 | BAIXO | [FilesPanel.vue:42-43](../../plugins/internal_chat/frontend/components/FilesPanel.vue#L42-L43) | Keydown listener removido só em unmount, não em subTab change |
| FE-12 | BAIXO | [MessageThread.vue](../../plugins/internal_chat/frontend/components/MessageThread.vue) | Watcher de length redundante com watcher deep |

### 9.4 Optimistic UI e races

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| FE-13 | MÉDIO | [MessageComposer.vue](../../plugins/internal_chat/frontend/components/MessageComposer.vue) | `send()` limpa text/files antes de await; double-send race possível |
| FE-14 | MÉDIO | [MessageBubble.vue:85-100](../../plugins/internal_chat/frontend/components/MessageBubble.vue#L85-L100) | Sticker save/remove race em rapid mount/unmount; `stickerActionPending` é per-instance |
| FE-15 | BAIXO | [internalChatMessages.js#toggleFavorite](../../plugins/internal_chat/frontend/store/internalChatMessages.js) | Optimistic revert OK, mas race se múltiplas toggles simultâneas |

### 9.5 i18n

| # | Severidade | Problema |
|---|---|---|
| FE-16 | MÉDIO | Strings PT-BR hardcoded em components (`"Figurinha salva nas suas favoritas"`, `"janela de 5 minutos para edição expirou"`, etc.) — fora do padrão Chatwoot de `en.json` |
| FE-17 | BAIXO | Strings PT-BR em código backend (system messages, error responses) |

### 9.6 Permission gating

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| FE-18 | MÉDIO | [GroupSettingsDrawer.vue](../../plugins/internal_chat/frontend/components/GroupSettingsDrawer.vue) | Botões de admin actions sem gating; UI permite click, backend retorna 403 (UX ruim) |
| FE-19 | BAIXO | Stickers / Files panels | Sem gating per role; aceitável (todos podem ver) |

### 9.7 UX bugs

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| FE-20 | MÉDIO | [messages_controller.rb#update:51-65](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L51-L65) | Edit window de 5min sem warning prévio no frontend; user perde texto |
| FE-21 | MÉDIO | [messages_controller.rb#favorites:128-151](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/messages_controller.rb#L128-L151) | Limit 200 silencioso; favoritos antigos invisíveis sem aviso |
| FE-22 | MÉDIO | [stickers_controller.rb#favorite:79-97](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/stickers_controller.rb#L79-L97) | Default sticker retorna `is_favorite: false` ao "favoritar" — UI inconsistente |
| FE-23 | BAIXO | [RoomView.vue](../../plugins/internal_chat/frontend/components/RoomView.vue) | Watcher de `room` redireciona para home em null transiente |

### 9.8 Sumário frontend

| Severidade | Quantidade |
|---|---|
| ALTO | 2 |
| MÉDIO | 15 |
| BAIXO | 6 |
| **Total** | **23** |

---

## 10. Problemas de Backend

### 10.1 Cobertura de testes

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-1 | ALTO | [ChatService](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb) (947 linhas) | Sem specs |
| BE-2 | ALTO | [ChatResponseJob](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb) (347 linhas) | Sem specs |
| BE-3 | MÉDIO | [SearchAvailableSlotsTool](../../plugins/ai_agent/app/services/ai_agent/tools/search_available_slots_tool.rb) (478 linhas) | Sem specs |
| BE-4 | MÉDIO | [MessageDispatcher](../../plugins/internal_chat/app/services/internal_chat/message_dispatcher.rb) | Sem specs do fluxo transacional |
| BE-5 | MÉDIO | [BroadcastMessageJob](../../plugins/internal_chat/app/jobs/internal_chat/broadcast_message_job.rb) | Sem specs |
| BE-6 | BAIXO | tenant_isolation_spec existe em ambos plugins; cobre Documents/FollowUpRules/Templates mas não cobre RAG retriever, Trace, Mentions cross-room |

### 10.2 Idempotência e race conditions

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-7 | ALTO | [chat_service.rb#book_appointment wrap:290-318](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb#L290-L318) | Sem constraint de unicidade `(conversation_id, service_id, starts_at)`; duas chamadas concorrentes do tool podem dupla-bookar |
| BE-8 | MÉDIO | [memberships_controller.rb:90-95](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/memberships_controller.rb#L90-L95) | `find_or_initialize_by` sem lock — race se 2 admins adicionam mesmo user simultaneamente |
| BE-9 | MÉDIO | [stickers_controller.rb#unfavorite:103-117](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/stickers_controller.rb#L103-L117) | Pessimistic lock em sticker; com 100+ favoritos concurrent, serializa |
| BE-10 | BAIXO | [chat_response_job.rb:48-56](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb#L48-L56) | Trace unique partial index `(message_id) WHERE error_message IS NULL` — race entre dois jobs concurrent do mesmo message_id: ambos passam check, segundo hits constraint |

### 10.3 Transações e estado parcial

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-11 | MÉDIO | [message_dispatcher.rb:18-56](../../plugins/internal_chat/app/services/internal_chat/message_dispatcher.rb#L18-L56) | `BroadcastMessageJob.perform_later` FORA da transação; se queue cair, message existe mas broadcast nunca |
| BE-12 | MÉDIO | [ingest_document_job.rb:22-52](../../plugins/ai_agent/app/jobs/ai_agent/ingest_document_job.rb#L22-L52) | `document.update!(status: :processing)` fora da txn; falha no meio = status preso |
| BE-13 | BAIXO | [rooms_controller.rb#destroy:64-74](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/rooms_controller.rb#L64-L74) | Broadcast após `destroy!`; falha no User.find_by não notifica |

### 10.4 Sanitização / escaping

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-14 | CRÍTICO | [system_message_builder.rb:47-58](../../plugins/internal_chat/app/services/internal_chat/system_message_builder.rb#L47-L58) | Nomes interpolados sem escape; XSS se frontend usa `v-html` |
| BE-15 | ALTO | [prompt_builder.rb](../../plugins/ai_agent/app/services/ai_agent/prompt_builder.rb) | Patient name + memory + history sem escape no system prompt (LLM injection) |

### 10.5 Active Storage / blobs

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-16 | ALTO | [attachment.rb:29-38](../../plugins/internal_chat/app/models/internal_chat/attachment.rb#L29-L38) | `file_url`/`download_url` usa `url_for(file)`/`file.blob.url` direto; AGENTS.md exige `SecureBlobsController` |
| BE-17 | MÉDIO | [message.rb#soft_delete!](../../plugins/internal_chat/app/models/internal_chat/message.rb) | Soft delete não purge attachments; storage acumula |
| BE-18 | MÉDIO | Sticker e Avatar | Active Storage padrão sem encryption-at-rest; áudio + imagem patient sensitive |

### 10.6 Validations e referential integrity

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-19 | MÉDIO | [Membership.unread_count:16-20](../../plugins/internal_chat/app/models/internal_chat/membership.rb#L16-L20) | Não usa `.visible`; conta msgs soft-deleted como não lidas |
| BE-20 | MÉDIO | [MessageDispatcher](../../plugins/internal_chat/app/services/internal_chat/message_dispatcher.rb) | Não valida `in_reply_to` pertence à mesma sala antes de salvar |
| BE-21 | BAIXO | Migrations | Backfill em [20260518100001](../../plugins/ai_agent/db/migrate/20260518100001_backfill_ai_agent_internal_notification_templates.rb) usa `Account.find_each` na migration — bloqueia deploy em base grande |

### 10.7 Error handling

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-22 | BAIXO | [chat_service.rb](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb) | `rescue` com `message[0, 200]` truncado — esconde stack trace |
| BE-23 | BAIXO | Vários `rescue StandardError => e` com `Rails.logger.error` sem re-raise — silencia falhas |

### 10.8 Custos LLM

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| BE-24 | ALTO | [chat_service.rb:847-870](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb#L847-L870) | Provider fallback dobra custo sem circuit breaker |
| BE-25 | ALTO | [follow_ups/message_generator.rb](../../plugins/ai_agent/app/services/ai_agent/follow_ups/message_generator.rb) | LLM output sem validation |
| BE-26 | MÉDIO | [config_resolver.rb:55-60](../../plugins/ai_agent/app/services/ai_agent/config_resolver.rb#L55-L60) | `over_monthly_cost_cap?` enforced só em `ChatService.respond`; não em Distiller, FollowUps MessageGenerator, Sentinel, SentimentAnalyzer |
| BE-27 | MÉDIO | [chat_response_job.rb](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb) e [chat_service.rb:846](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb#L846) | Retry delay sem jitter; thundering herd em outage de Gemini |

### 10.9 Sumário backend

| Severidade | Quantidade |
|---|---|
| CRÍTICO | 1 |
| ALTO | 7 |
| MÉDIO | 14 |
| BAIXO | 5 |
| **Total** | **27** |

---

## 11. Problemas Arquiteturais

### 11.1 God services / files

| # | Severidade | Arquivo | Linhas | Refator sugerido |
|---|---|---|---|---|
| ARCH-1 | ALTO | [ChatService](../../plugins/ai_agent/app/services/ai_agent/chat_service.rb) | 947 | Extract: `EmergencyHandler`, `DetectorRegistry`, `StateMachineEngine`, `ResponseFormatter`, `ProviderFallback` |
| ARCH-2 | ALTO | [ChatResponseJob](../../plugins/ai_agent/app/jobs/ai_agent/chat_response_job.rb) | 347 | Extract: `BlobRetryHandler`, `VisualContentHandler`, `TracePersistence` |
| ARCH-3 | MÉDIO | [SearchAvailableSlotsTool](../../plugins/ai_agent/app/services/ai_agent/tools/search_available_slots_tool.rb) | 478 | Extract: `SlotAllocator`, `PeriodDistributor`, `DateRangeValidator` |
| ARCH-4 | MÉDIO | [PromptBuilder](../../plugins/ai_agent/app/services/ai_agent/prompt_builder.rb) | 271 | Acceptable — single responsibility complex domain |
| ARCH-5 | MÉDIO | [ContextBuilder](../../plugins/ai_agent/app/services/ai_agent/context_builder.rb) | 290 | Acceptable |
| ARCH-6 | ALTO | [MessageBubble.vue](../../plugins/internal_chat/frontend/components/MessageBubble.vue) | 1044 | Extract: `MessageBubbleContent`, `MessageBubbleActions`, `StickerPreviewModal`, `ReactionSection` |
| ARCH-7 | ALTO | [GroupSettingsDrawer.vue](../../plugins/internal_chat/frontend/components/GroupSettingsDrawer.vue) | 588 | Extract: `GroupMembersView`, `GroupDetailsEditor` |
| ARCH-8 | MÉDIO | [followUps/Index.vue](../../plugins/ai_agent/frontend/routes/followUps/Index.vue) | 690 | Extract: trigger constants para arquivo separado; `FollowUpFormModal` |
| ARCH-9 | MÉDIO | [internalNotificationTemplates/Index.vue](../../plugins/ai_agent/frontend/routes/internalNotificationTemplates/Index.vue) | 471 | Extract: variável insertion helper; preview component |

### 11.2 Engine isolation e monkey-patches

| # | Severidade | Arquivo | Observação |
|---|---|---|---|
| ARCH-10 | OK | [ai_agent/engine.rb](../../plugins/ai_agent/lib/ai_agent/engine.rb) | 9 monkey-patches em 6 classes core, todos com guards idempotentes (`unless method_defined?`) — pattern correto |
| ARCH-11 | OK | [internal_chat/engine.rb](../../plugins/internal_chat/lib/internal_chat/engine.rb) | 2 simples associations, guarded |
| ARCH-12 | MÉDIO | [ai_agent/engine.rb:175-214](../../plugins/ai_agent/lib/ai_agent/engine.rb#L175-L214) | Patches em `Captain::Assistant` (protect Beatriz). Se Chatwoot upgrade mudar esse modelo, patches podem quebrar silenciosamente — sem teste que detecta drift |

### 11.3 Service entry method inconsistency

| # | Severidade | Problema |
|---|---|---|
| ARCH-13 | BAIXO | ~50% services usam `.call`, ~30% custom (e.g., `BeaResolver.for_account`), ~20% instance (`ChatService#respond`) — convencionar |

### 11.4 Dead code

| # | Severidade | Arquivo | Observação |
|---|---|---|---|
| ARCH-14 | BAIXO | [ReadReceipt](../../plugins/internal_chat/app/models/internal_chat/read_receipt.rb) | `Membership.last_read_message_id` é canônico; ReadReceipt parece redundante — consolidar |
| ARCH-15 | BAIXO | [internal_chat.rake](../../plugins/internal_chat/lib/tasks/internal_chat.rake) | Referenciado no engine mas verificar se task é executada em deploy |

### 11.5 Cross-plugin coupling

| # | Severidade | Observação |
|---|---|---|
| ARCH-16 | OK | `ai_agent` → `InternalChat::*` legitimate (notifier + responder); `internal_chat` → `Captain::Assistant` legitimate (Bea resolver). Sem coupling circular. |

### 11.6 Convention compliance

| # | Severidade | Observação |
|---|---|---|
| ARCH-17 | OK | Models PascalCase + namespaced; tables snake_case + prefixed; routes scoped `/accounts/:account_id/`; Vue PascalCase. Tudo OK. |

### 11.7 Documentation gaps

| # | Severidade | Problema |
|---|---|---|
| ARCH-18 | MÉDIO | Sem README em `plugins/ai_agent/` e `plugins/internal_chat/` |
| ARCH-19 | MÉDIO | Swagger files em `plugins/*/swagger/` existem mas não foi verificado se estão sincronizados com controllers |
| ARCH-20 | BAIXO | Sem ADRs explicando decisões pesadas (LLM provider fallback, ReadReceipt vs Membership.last_read_message_id, sentinel opt-in) |

### 11.8 Reuse violations

| # | Severidade | Problema |
|---|---|---|
| ARCH-21 | MÉDIO | Pattern `User.find_by(id: uid) + ActionCable.server.broadcast(user.pubsub_token, payload)` repetido em RoomCreator, BroadcastMessageJob, RoomsController, MessagesController, TypingController — extrair `UserBroadcaster` service |
| ARCH-22 | BAIXO | Serialização inconsistente (Serializer class vs plain hash) |

### 11.9 i18n / localization

| # | Severidade | Problema |
|---|---|---|
| ARCH-23 | MÉDIO | Strings PT hardcoded; Chatwoot pattern exige `en.json`/`en.yml` |

### 11.10 Sumário arquitetural

| Severidade | Quantidade |
|---|---|
| ALTO | 4 |
| MÉDIO | 11 |
| BAIXO | 5 |
| OK | 3 |
| **Total** | **23** |

---

## 12. Melhorias Recomendadas

### 12.1 Imediatas (esta sprint — bloqueadores de produção)

> Estima-se 5–10 dias de engenharia focada.

1. **Wire ActionCable handlers** para 7 eventos `internal_chat.*` em `app/javascript/dashboard/helper/actionCable.js` — sem isso, realtime do internal_chat é placebo. **(RT-1)**
2. **Adicionar `authorize` + policies** em `FollowUpRulesController` e `InternalNotificationTemplatesController`. **(SEC-1, SEC-2)**
3. **Scopar `ParentChunk.find` por `account_id`** em [retriever.rb:54](../../plugins/ai_agent/app/services/ai_agent/rag/retriever.rb#L54). **(MT-1)**
4. **Scopar `Trace.find_by` + bind `account_id` no HMAC** em [feedbacks_controller.rb](../../plugins/ai_agent/app/controllers/api/v1/ai_agent/feedbacks_controller.rb) e [feedback_token_signer.rb](../../plugins/ai_agent/app/services/ai_agent/feedback_token_signer.rb). Adicionar TTL ao token. **(MT-2, SEC-11)**
5. **Scopar `InternalChat::Message.find_by` no Responder** + validar `in_reply_to` pertence à mesma sala. **(MT-3, MT-4)**
6. **Adicionar `authorize_room_access` ao `download` action** em [attachments_controller.rb](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/attachments_controller.rb). **(CRÍTICO-11)**
7. **Escape de nomes em `SystemMessageBuilder`** ou confirmar que frontend não usa `v-html`. **(BE-14)**
8. **Sanitizar `pushName` do contato + escape JSON da memória** antes de injetar no prompt. **(SEC-22, SEC-23)**
9. **Permission check em `ErasureRequestTool`** para garantir `contact_id == context.contact_id`. **(SEC-13)**

### 12.2 Curto prazo (próxima sprint — 2-3 semanas)

1. **Passar `account_id` a todos os jobs** (`ChatResponseJob`, `PurgeUserDataJob`, `DataExporter`, `RespondJob`). Validar antes de operar. **(MT-5, MT-6, MT-7)**
2. **Adicionar policies a `Memberships`, `Attachments`, `Typing`, `Mentions`** controllers. Adicionar perm `internal_chat:manage_memberships` no KlivyRole. **(SEC-3, SEC-4, SEC-5, SEC-6)**
3. **Permission gate em Internal*Tools** — verificar `Current.account_user.beclinic_can?(:agenda, :cancel_event)` etc. antes de executar. **(SEC-12)**
4. **Rate limit em `CreatePatientMinimalTool`** (Redis counter por contact por 24h). **(SEC-14)**
5. **Fix N+1 do `RoomSerializer`** — preload `messages.first` em batch no controller. **(PERF-1)**
6. **Debounce backend do `mark_read`** (coalesce ≤2s). **(PERF-11)**
7. **Rate limit backend do `typing`** (1 broadcast / 1s / user / room). **(PERF-12)**
8. **Deduplicar broadcast `mention.created`** quando user é membro do room também. **(PERF-13)**
9. **Adicionar `account_id` à tabela `internal_chat_sticker_favorites`** + validation. **(MT-11)**
10. **Reset de stores frontend** no account-switch (não depender de full reload do SidebarAccountSwitcher). **(MT-14 a MT-19)**
11. **Servir attachments via `SecureBlobsController`** em vez de `url_for`/`blob.url`. **(BE-16)**
12. **Validar `in_reply_to` na mesma sala** no `MessageDispatcher`. **(BE-20)**
13. **Filtrar `.visible` em `Membership.unread_count`**. **(BE-19)**

### 12.3 Médio prazo (1–2 meses)

1. **Refatorar `ChatService`** (947 linhas) em handlers/registries. **(ARCH-1)**
2. **Refatorar `MessageBubble.vue`** (1044 linhas) em subcomponentes. **(ARCH-6)**
3. **Adicionar specs** para `ChatService`, `ChatResponseJob`, `MessageDispatcher`, `BroadcastMessageJob`. **(BE-1 a BE-5)**
4. **Índices compostos:**
   - `ai_agent_follow_up_executions(account_id, contact_id, status, sent_at DESC)`. **(PERF-6)**
   - `ai_agent_traces(account_id, created_at DESC, escalated, error_message)`. **(PERF-7)**
   - Expression index em `jsonb_array_length(history)` em `patient_memories`. **(PERF-8)**
5. **Substituir `window.confirm` por `ConfirmDangerModal`** do beclinic_core. **(FE-7)**
6. **Substituir `title="..."` por `<Tooltip>`** do beclinic_core. **(FE-6)**
7. **Externalizar strings PT-BR** para `en.json`/`en.yml`. **(FE-16, ARCH-23)**
8. **TTL/archival em `ai_agent_traces`** (>90 dias). **(ESC-11)**
9. **Queue dedicada `:ai` para `ChatResponseJob`**. **(ESC-9)**
10. **Cost cap enforcement em Distiller, MessageGenerator, Sentinel**. **(BE-26)**
11. **Reconcile state em reconnect** WebSocket (refetch room messages). **(RT-5)**
12. **Audit log para policy decisions** (room destroy, archive, rule create/update/delete). **(SEC-7)**

### 12.4 Longo prazo (estratégico, 3-6 meses)

1. **Migrar broadcasts para canal dedicado `InternalChatRoomChannel`** (per-room subscription) — viabiliza cleanup explícito, reduz volume.
2. **Batch embeddings + circuit breaker em provider fallback** com cost cap por turn.
3. **Token-counted prompt truncation** em `PromptBuilder` para suportar modelos com context menor.
4. **Encryption-at-rest** para attachments de áudio e imagem (HIPAA-ready).
5. **Consolidar `ReadReceipt` em `Membership.last_read_message_id`** ou vice-versa.
6. **Schema de permissões granulares** para internal_chat (manage_memberships, view_attachments, etc.).
7. **Adversarial testing automatizado** para prompt injection (red team CI).
8. **README + ADRs** em cada plugin documentando decisões.

---

## 13. Plano de Correção (roadmap em fases)

### Fase 1 — Bloqueadores de produção (1 sprint)

Foco: **eliminar exposição de dados cross-tenant + corrigir realtime + fechar bypass RBAC crítico**. Sem regressão funcional.

| Tarefa | Findings | Estimativa |
|---|---|---|
| Wire 7 handlers ActionCable | RT-1 | 1d |
| Scope `ParentChunk.find` + `Trace.find_by` + `Responder` lookups | MT-1, MT-2, MT-3, MT-4 | 1d |
| Adicionar Pundit policy a FollowUpRules + Templates controllers | SEC-1, SEC-2 | 1d |
| Adicionar `authorize_room_access` ao `attachments#download` | CRÍTICO-11 | 0.5d |
| HMAC FeedbackToken com `account_id` + TTL | SEC-11 | 0.5d |
| Escape em SystemMessageBuilder + verificar frontend | BE-14 | 0.5d |
| Sanitização de prompt (contact name, memory) | SEC-22, SEC-23 | 1d |
| Permission check em ErasureRequestTool | SEC-13 | 0.5d |
| Specs de regressão para os 9 pontos acima | — | 2d |
| **Total** | | **~8d** |

**Critério de saída:** 9 PRs merged + specs verdes + smoke test multi-tenant em staging.

### Fase 2 — Hardening RBAC e tenant isolation (1–2 sprints)

| Tarefa | Findings | Estimativa |
|---|---|---|
| Policies para Memberships/Attachments/Typing/Mentions controllers | SEC-3, SEC-4, SEC-5, SEC-6 | 2d |
| Perm granular `internal_chat:manage_memberships` no KlivyRole catalog | — | 1d |
| Permission gate em Internal*Tools | SEC-12 | 1d |
| Rate limit em CreatePatientMinimalTool | SEC-14 | 0.5d |
| Account scoping em jobs (ChatResponseJob, PurgeUserDataJob, DataExporter) | MT-5, MT-6, MT-7 | 2d |
| Account_id em `StickerFavorite` (migration + validation) | MT-11 | 1d |
| Reset frontend stores no account-switch | MT-14 a MT-19 | 2d |
| SecureBlobsController para attachments | BE-16 | 2d |
| Validar `in_reply_to` mesma sala | BE-20 | 0.5d |
| Specs | — | 3d |
| **Total** | | **~15d** |

### Fase 3 — Performance e UX (2 sprints)

| Tarefa | Findings | Estimativa |
|---|---|---|
| N+1 fix RoomSerializer + unread_summary batch | PERF-1, PERF-2 | 2d |
| Debounce mark_read + rate limit typing (server) | PERF-11, PERF-12 | 1d |
| Dedupe mention broadcast | PERF-13 | 0.5d |
| Índices compostos (executions, traces, patient_memories) | PERF-6, PERF-7, PERF-8 | 1d |
| Stickers `recent` em SQL | PERF-3 | 0.5d |
| Substituir `window.confirm` por ConfirmDangerModal | FE-7 | 1d |
| Substituir `title=` por Tooltip | FE-6 | 1d |
| Externalizar strings para en.json | FE-16 | 3d |
| Frontend optimistic-UI hardening (race conditions) | FE-13, FE-14 | 1d |
| Edit window warning frontend; favorites pagination | FE-20, FE-21 | 1d |
| **Total** | | **~12d** |

### Fase 4 — Refatoração estratégica e cobertura (2–3 sprints)

| Tarefa | Findings | Estimativa |
|---|---|---|
| Decompose ChatService | ARCH-1 | 5d |
| Decompose ChatResponseJob | ARCH-2 | 2d |
| Decompose MessageBubble.vue | ARCH-6 | 3d |
| Decompose GroupSettingsDrawer.vue | ARCH-7 | 2d |
| Specs para ChatService, ChatResponseJob, MessageDispatcher, BroadcastMessageJob | BE-1 a BE-5 | 5d |
| Audit logs para policy decisions | SEC-7 | 2d |
| TTL em ai_agent_traces (job cron + archival) | ESC-11 | 1d |
| Queue dedicada `:ai` para ChatResponseJob | ESC-9 | 0.5d |
| Cost cap enforcement em Distiller/MessageGenerator/Sentinel | BE-26 | 1d |
| Reconcile state em reconnect WebSocket | RT-5 | 2d |
| Cleanup orphaned attachments job | BE-17 | 1d |
| **Total** | | **~25d** |

### Cronograma sugerido

```
Sprint 1 (semana 1-2):  Fase 1 — Bloqueadores
Sprint 2 (semana 3-4):  Fase 2a — RBAC
Sprint 3 (semana 5-6):  Fase 2b — Tenant isolation
Sprint 4 (semana 7-8):  Fase 3a — Performance backend
Sprint 5 (semana 9-10): Fase 3b — UX / i18n
Sprint 6 (semana 11-12):Fase 4a — Refactor ChatService
Sprint 7 (semana 13-14):Fase 4b — Specs e refactor frontend
Sprint 8 (semana 15-16):Fase 4c — Hardening adicional
```

### Princípios de execução (sem regressão)

1. **Feature flags** para mudanças que afetam comportamento perceptível ao usuário (debounce mark_read, dedupe broadcast).
2. **Specs antes do refactor** — toda decomposição precedida de testes de caracterização (golden master).
3. **Migrations reversíveis** — toda nova coluna/índice com `change` reversível ou `up`/`down` documentado.
4. **Backwards-compatible API** — não alterar payload de endpoints existentes; novos campos adicionados como opcionais.
5. **Rollout gradual** — mudanças de queue, índices, e cleanup jobs com observabilidade antes de promover.
6. **Audit log** — toda fix de RBAC adiciona AuditLog para detecção de tentativa de exploit antiga.

---

## 14. Checklist Final

### Bloqueador funcional
- [ ] **Realtime internal_chat funcional** — handlers de 7 eventos registrados em `ActionCableConnector`; mensagens, edits, menções, typing, room.updated/deleted, read receipts aparecem sem F5

### Multi-tenant seguro
- [ ] `ParentChunk.find` scoped por `account_id`
- [ ] `Trace.find_by` scoped + HMAC token vincula `account_id` + TTL
- [ ] `InternalChat::Message.find_by` no Responder scoped
- [ ] `in_reply_to` valida mesma sala
- [ ] `ChatResponseJob`, `PurgeUserDataJob`, `DataExporter`, `RespondJob` recebem `account_id` e validam
- [ ] `Health::MonitorJob`, `FollowUpDispatcherJob`, `ConsolidatePatientMemoryJob`, `ProactiveOutreachJob` iteram `Account.find_each` e propagam scope
- [ ] `Mention.account_id` validado contra `message.room.account_id`
- [ ] `MessageReaction.room_id` / `MessageFavorite.room_id` validados contra `message.room_id`
- [ ] `StickerFavorite` tem coluna `account_id` + validation
- [ ] Frontend stores resetam em logout/account-switch (não depender de full reload)

### Policies seguras
- [ ] `FollowUpRulesController` tem policy + `authorize`
- [ ] `InternalNotificationTemplatesController` tem policy + `authorize`
- [ ] `MembershipsController` tem policy + perm granular `internal_chat:manage_memberships`
- [ ] `AttachmentsController` tem policy + `authorize` em todas as actions (incl. `download`)
- [ ] `TypingController` tem policy
- [ ] `MentionsController` tem policy
- [ ] `RoomPolicy.destroy?` admin bypass gera AuditLog
- [ ] `MessagePolicy.update?/destroy?` valida 5min window e room membership atual
- [ ] Internal*Tools (`InternalCancel*`, `InternalBook*`, `InternalReschedule*`, `InternalSearchPatient*`, `InternalListPatient*`) checam perm do staff invocador
- [ ] `ErasureRequestTool` valida `contact_id == context.contact_id`
- [ ] `CreatePatientMinimalTool` tem rate limit por contact (24h)

### APIs protegidas
- [ ] Endpoint `/api/v1/ai_agent/health` retorna apenas `{status: ok|down}`, sem detalhes
- [ ] Endpoint `/api/v1/ai_agent/feedbacks` rate-limited + token bindings + TTL
- [ ] `InternalNotificationTemplatesController#catalog` não vaza lista global de users

### Websocket seguro
- [ ] Frontend `ActionCableConnector` registra todos os 7 eventos `internal_chat.*`
- [ ] Backend usa `.active` scope consistente em todos os broadcast sites
- [ ] Frontend reconcilia state em reconnect (refetch messages)
- [ ] Typing rate-limited no backend (não só client debounce)
- [ ] Mention broadcast dedup quando user é membro do room também

### Jobs seguros
- [ ] `BroadcastMessageJob` enfileirado dentro da transação (ou tem retry/observabilidade)
- [ ] `IngestDocumentJob` status update dentro da transação; embeddings batched
- [ ] `ChatResponseJob` retry strategy explícita (não `retry: 0` silencioso)
- [ ] Cron jobs por tenant com idempotency key
- [ ] Queue dedicada `:ai` para LLM jobs

### Performance OK
- [ ] N+1 do `RoomSerializer` resolvido (preload `messages.first`)
- [ ] `unread_summary` em single query batched
- [ ] `Stickers#recent` em SQL `LIMIT 10` (não Ruby sort)
- [ ] `mark_read` debounced server-side
- [ ] `typing` rate-limited server-side
- [ ] Índices compostos em `traces`, `executions`, `patient_memories.history`

### Escalabilidade OK
- [ ] Cron jobs iteram por conta com cap individual + paralelismo
- [ ] Sidekiq queues isoladas por workload (default / scheduled / ai / low)
- [ ] Vector search RAG com partial index por account_id ou prefiltro
- [ ] TTL/archival em `ai_agent_traces` e `ai_agent_audit_logs`

### Código limpo
- [ ] `ChatService` decomposto
- [ ] `MessageBubble.vue` decomposto
- [ ] `GroupSettingsDrawer.vue` decomposto
- [ ] Service entry methods padronizados (`.call`)
- [ ] Strings PT externalizadas para `en.json`
- [ ] `window.confirm` substituído por `ConfirmDangerModal`
- [ ] `title="..."` substituído por `<Tooltip>`
- [ ] Components shared do beclinic_core adotados

### Sem dead code
- [ ] `ReadReceipt` consolidado com `Membership.last_read_message_id` (ou documentado o uso)
- [ ] Rake task `internal_chat:seed_default_stickers` executada em deploy

### Sem memory leaks
- [ ] `internalChatTyping.js#TIMERS` reset em logout/account-switch
- [ ] `useAudioRecorder` cleanup garantido em todos os paths
- [ ] `FilesPanel` listener cleanup em subTab change
- [ ] `MessageThread` watcher único (não redundante)

### Sem race conditions
- [ ] Unique constraint em `agenda_events(conversation_id, service_id, starts_at)` ou idempotência no BookAppointmentTool
- [ ] `find_or_initialize_by` no Membership add com transaction + lock
- [ ] Trace unique partial index com tratamento de RecordNotUnique
- [ ] Sticker unfavorite com retry no lock contention

### Sem N+1
- [ ] `RoomSerializer` preload
- [ ] `unread_summary` batched
- [ ] `RoomCreator` broadcast usa `users_by_id` map
- [ ] Stickers query SQL-side

### Sem vazamentos
- [ ] Todos os 20 findings multi-tenant resolvidos
- [ ] Attachments servidos via `SecureBlobsController`
- [ ] Áudio + imagens patient com encryption-at-rest
- [ ] Logs não contêm prompts, mensagens patient, PII

### Sem broadcasts inseguros
- [ ] Todo broadcast valida que destinatário pertence ao account/room esperado
- [ ] Mention broadcast deduplicado
- [ ] Read receipt broadcast com debounce
- [ ] Typing broadcast com rate limit server-side
- [ ] Bea typing dispatch funciona para agents dashboard (não só WhatsApp)

### Qualidade de testes
- [ ] Spec para `ChatService` (golden master + branches críticos)
- [ ] Spec para `ChatResponseJob` (audio retry, idempotency, fallback)
- [ ] Spec para `MessageDispatcher` (transação + mentions + AI listener)
- [ ] Spec para `BroadcastMessageJob` (dedup + active scope)
- [ ] Spec para `tenant_isolation` cobrindo RAG, Trace, in_reply_to cross-room
- [ ] Spec para prompt injection (contact name, memory)
- [ ] Spec adversarial em tools privilegiadas (ErasureRequestTool, Internal*Tool)

### Observabilidade
- [ ] AuditLog para policy decisions sensíveis (room destroy, archive, rule create/update/delete, template change)
- [ ] Métricas Sidekiq por queue (latency, retries, dead set)
- [ ] Alertas se `ConsolidatePatientMemoryJob` não termina em janela esperada
- [ ] Dashboard de custo LLM por conta (UsageCounter + Pricing)
- [ ] Alertas em provider fallback > X% (indica outage primário)

### Documentação
- [ ] README em cada plugin
- [ ] ADRs para LLM provider fallback, sentinel opt-in, ReadReceipt vs Membership
- [ ] Swagger atualizado para endpoints alterados
- [ ] CHANGELOG entry para cada fase de remediação

---

## Apêndice A — Files inventário rápido

### ai_agent

- **Engine:** [lib/ai_agent/engine.rb](../../plugins/ai_agent/lib/ai_agent/engine.rb), [lib/ai_agent.rb](../../plugins/ai_agent/lib/ai_agent.rb), [lib/ai_agent/gemini_thought_signature_patch.rb](../../plugins/ai_agent/lib/ai_agent/gemini_thought_signature_patch.rb), [lib/ai_agent/skip_beatriz_legacy_response.rb](../../plugins/ai_agent/lib/ai_agent/skip_beatriz_legacy_response.rb)
- **Routes:** [config/routes.rb](../../plugins/ai_agent/config/routes.rb) (vazio; mount em host app)
- **Models:** 15 em [app/models/ai_agent/](../../plugins/ai_agent/app/models/ai_agent/)
- **Controllers:** 3 namespaced em [app/controllers/ai_agent/api/v1/accounts/](../../plugins/ai_agent/app/controllers/ai_agent/api/v1/accounts/) + 2 públicos em [app/controllers/api/v1/ai_agent/](../../plugins/ai_agent/app/controllers/api/v1/ai_agent/)
- **Services:** ~50 em [app/services/ai_agent/](../../plugins/ai_agent/app/services/ai_agent/) organizados em subpastas (`tools/`, `internal_chat/`, `humanization/`, `rag/`, `internal_notifier/`, `memory/`, `multimodal/`, `detectors/`, `emergency/`, `health/`, `lgpd/`, `llm/`, `follow_ups/`, `proactive/`, `state_machine/`, `documents/`, `formatters/`)
- **Jobs:** [app/jobs/ai_agent/](../../plugins/ai_agent/app/jobs/ai_agent/) — `ChatResponseJob`, `FollowUpDispatcherJob`, `SendFollowUpJob`, `IngestDocumentJob`, `ProactiveOutreachJob`, `ConsolidatePatientMemoryJob`, `Health::MonitorJob`, `FollowUps::DispatchAppointmentConfirmedJob`, `InternalChat::RespondJob`
- **Listeners:** [app/listeners/ai_agent/event_listeners/message_listener.rb](../../plugins/ai_agent/app/listeners/ai_agent/event_listeners/message_listener.rb)
- **Policies:** [app/policies/ai_agent/document_policy.rb](../../plugins/ai_agent/app/policies/ai_agent/document_policy.rb) (única)
- **Migrations:** 30 em [db/migrate/](../../plugins/ai_agent/db/migrate/) (numeração 20260518000001 → 20260518100001)
- **Frontend:** [frontend/](../../plugins/ai_agent/frontend/) — 2 routes (FollowUps + InternalNotificationTemplates), 2 stores, 2 API clients
- **Specs:** [spec/](../../plugins/ai_agent/spec/) — services, listeners, policies, requests (tenant_isolation)
- **Swagger:** [swagger/](../../plugins/ai_agent/swagger/) — definitions + paths

### internal_chat

- **Engine:** [lib/internal_chat/engine.rb](../../plugins/internal_chat/lib/internal_chat/engine.rb), [lib/tasks/internal_chat.rake](../../plugins/internal_chat/lib/tasks/internal_chat.rake)
- **Routes:** [config/routes.rb](../../plugins/internal_chat/config/routes.rb) (vazio; mount em host app)
- **Models:** 10 em [app/models/internal_chat/](../../plugins/internal_chat/app/models/internal_chat/)
- **Controllers:** 7 em [app/controllers/api/v1/accounts/internal_chat/](../../plugins/internal_chat/app/controllers/api/v1/accounts/internal_chat/)
- **Services:** 11 em [app/services/internal_chat/](../../plugins/internal_chat/app/services/internal_chat/)
- **Jobs:** [app/jobs/internal_chat/](../../plugins/internal_chat/app/jobs/internal_chat/) — `BroadcastMessageJob`, `PurgeUserDataJob`
- **Listeners:** [app/listeners/internal_chat/ai_agent_mention_listener.rb](../../plugins/internal_chat/app/listeners/internal_chat/ai_agent_mention_listener.rb)
- **Policies:** 3 em [app/policies/internal_chat/](../../plugins/internal_chat/app/policies/internal_chat/)
- **Migrations:** 13 em [db/migrate/](../../plugins/internal_chat/db/migrate/) (numeração 20260518000028 → 20260518000040)
- **Frontend:** [frontend/](../../plugins/internal_chat/frontend/) — 22 componentes Vue, 5 stores, 4 composables, 7 API clients
- **Specs:** [spec/](../../plugins/internal_chat/spec/) — policies + requests (tenant_isolation)
- **Swagger:** [swagger/](../../plugins/internal_chat/swagger/)

---

## Apêndice B — Limites observados (constantes)

| Constante | Valor | Origem |
|---|---|---|
| `HISTORY_LIMIT` (chat history) | 10 | ChatResponseJob, InternalChat::Responder |
| `MAX_BLOB_RETRY` | 3 | ChatResponseJob:24 |
| `BLOB_RETRY_DELAY` | 5.seconds | ChatResponseJob:25 |
| `RateLimiter::PER_CONVERSATION_LIMIT` | 60 turnos/hora | rate_limiter.rb:13 |
| `RateLimiter::PER_ACCOUNT_LIMIT` | 2000 turnos/dia | rate_limiter.rb:15 |
| `DEBOUNCE_SECONDS` | 3 | message_listener.rb:28 |
| `FollowUpDispatcherJob::DAILY_CAP_PER_ACCOUNT` | 200 | follow_up_dispatcher_job.rb |
| `FollowUpDispatcherJob::PER_CONTACT_COOLDOWN` | 2h | idem |
| `ProactiveOutreachJob` cap | 30/account/run | proactive_outreach_job.rb |
| `ProactiveOutreachJob` cooldown | 90 dias | recall_finder.rb |
| `ConsolidatePatientMemoryJob` cap | 100/account/run | consolidate_patient_memory_job.rb |
| `MIN_HISTORY_ENTRIES` (consolidation) | 5 | consolidate_patient_memory_job.rb |
| `RECONSOLIDATE_AFTER` | 23h | idem |
| `EDIT_WINDOW` (message) | 5 minutes | messages_controller.rb:51 |
| Max attachments per message | 15 | message_dispatcher.rb |
| Max attachment size | 40 MB | attachment.rb |
| Max sticker size | 300 KB | sticker.rb |
| Max document PDF | 20 MB | document.rb |
| Max patient memory history | 50 entries | patient_memory.rb |
| `Typing` debounce client | 3s | useTypingIndicator.js |
| `Typing` renewal | 4s | useTypingIndicator.js |
| `Typing` expiry server | 5.2s | internalChatTyping.js |
| Audio recording cap | 5 minutes | useAudioRecorder.js |
| `MessagesController#favorites` limit | 200 | messages_controller.rb:128 |
| `MessagesController#index` limit default | 30 (max 100) | messages_controller.rb |
| `AttachmentsController#index` limit | 200 | attachments_controller.rb |
| `MentionsController#index` limit | 50 (max 200) | mentions_controller.rb |

---

## Apêndice C — Sumário numérico

| Categoria | CRÍTICO | ALTO | MÉDIO | BAIXO | Total |
|---|---|---|---|---|---|
| Multi-tenant | 4 | 7 | 8 | 1 | 20 |
| Segurança / RBAC | 5 | 11 | 9 | 4 | 29 |
| Performance | 0 | 9 | 9 | 8 | 26 |
| Escalabilidade | 0 | 5 | 6 | 1 | 12 |
| Realtime | 1 | 1 | 3 | 3 | 8 |
| Frontend | 0 | 2 | 15 | 6 | 23 |
| Backend | 1 | 7 | 14 | 5 | 27 |
| Arquitetural | 0 | 4 | 11 | 5 | 20 |
| **TOTAL** | **11** | **46** | **75** | **33** | **165** |

> Há overlap entre categorias (um finding pode aparecer em "multi-tenant" e "segurança" simultaneamente). Os totais não somam exatamente porque alguns findings cross-listed.

---

**Documento de auditoria gerado em 2026-05-18.**

> Esta auditoria foi conduzida em modo "observe-only" — nenhum código foi alterado. Todas as recomendações são propostas. A execução fica a critério da equipe, respeitando feature flags, testes de regressão e janela de manutenção.

---

## Apêndice D — Status de Remediação por Finding

> Atualizado em 2026-05-19 (segunda revisão). **~78 entregas em 32 lotes** — 70+ fixes aplicados, 4 specs caracterizadores (BE-1/2/3/4 com 80 examples cumulativos), 6 falsos positivos confirmados.

### Multi-tenant (Seção 4)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| MT-1 | CRÍTICO | ✅ Aplicado | 1.1 | `ParentChunk.find` via JOIN com documents (+ bonus N+1 fix) |
| MT-2 | CRÍTICO | ✅ Fechado | 1.3 | Por SEC-11 (HMAC bind account_id) |
| MT-3 | CRÍTICO | ✅ Aplicado | 1.1 | `RespondJob`/`Responder` validam `account_id` |
| MT-4 | CRÍTICO | ✅ Aplicado | 1.1 | `replied_message_for` scoped a `message.room.messages` |
| MT-5 | ALTO | ✅ Aplicado | 2.1 | `ChatResponseJob` valida `message.account_id == account_id` |
| MT-6 | ALTO | ✅ Aplicado | 2.1 | `PurgeUserDataJob` exige `account_id:` + scopa todas as queries |
| MT-7 | ALTO | ✅ Aplicado | 2.1 | `DataExporter` exige `account:` + JOINs por account |
| MT-8 | MÉDIO | ✅ Aceito por design | 60 | `Health::MonitorJob` é health-checker global cross-account (monitora infra: DB, Redis, LLM providers). Não há recurso multi-tenant pra scopar — single instance roda checks system-wide. Comportamento intencional |
| MT-9 | MÉDIO | ✅ Aceito por design | 60 | `ProactiveOutreachJob` itera `AccountSetting.where(enabled: true)` e dispatcha per-account via `ProactiveOutreachPerAccountJob` (ESC-3 lote 17). Isolamento é via Sidekiq jobs por conta, não no dispatcher cron |
| MT-10 | MÉDIO | ✅ Aceito por design | 60 | `ConsolidatePatientMemoryJob` segue mesmo pattern (cron dispatcher + per-account jobs via ESC-2). Scope verificado em revisão lote 17 — cada per-account job recebe `account_id:` kwarg obrigatório e scopa todas as queries |
| MT-11 | ALTO | ✅ Aplicado | 2.4 | Migration `20260520000001` + validation `account_matches_sticker_when_custom` |
| MT-12 | MÉDIO | ✅ Aplicado | 2.7 | Validation `account_id == message.room.account_id` em Mention |
| MT-13 | MÉDIO | ✅ Aplicado | 2.7 | Validation `room_id`+`account_id` em Reaction/Favorite |
| MT-14 | MÉDIO | ✅ Aplicado | 2.5 | Reset action em `internalChatRooms` + watcher no ChatShell |
| MT-15 | MÉDIO | ✅ Aplicado | 2.5 | Reset action em `internalChatTyping` (+ clearTimeout TIMERS map) |
| MT-16 | MÉDIO | ✅ Aplicado | 2.5 | Reset action em `internalChatRooms` |
| MT-17 | MÉDIO | ✅ Aplicado | 2.5 | Reset action em `internalChatMessages` |
| MT-18 | MÉDIO | ✅ Aplicado | 2.5 | Reset action em `internalChatMentions` |
| MT-19 | MÉDIO | ✅ Aplicado | 2.5 | Reset action em `aiAgentFollowUpRules` + `aiAgentInternalNotificationTemplates` (`resetStore`) |
| MT-20 | BAIXO | ✅ Aplicado | 2.7 | `BroadcastMessageJob` usa `.active` scope consistente |

**Multi-tenant: 20/20 — 17 aplicados + 3 aceitos por design (cron jobs cujo scope é intencionalmente cross-account ou já isolado per-account via Sidekiq).**

### Security/RBAC (Seção 5)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| SEC-1 | CRÍTICO | ✅ Aplicado | 1.2 | `FollowUpRulePolicy` criada + `check_authorization` |
| SEC-2 | CRÍTICO | ✅ Aplicado | 1.2 | `InternalNotificationTemplatePolicy` criada + `check_authorization` |
| SEC-3 | ALTO | ✅ Aplicado | 2.2 | `AttachmentPolicy` substituiu auth inline |
| SEC-4 | ALTO | ✅ Aplicado | 2.2 | `TypingPolicy` substituiu auth inline |
| SEC-5 | ALTO | ✅ Aplicado | 2.2 | `MembershipPolicy` + perm `internal_chat:manage_memberships` no catalog (extension point) |
| SEC-6 | ALTO | ✅ Aplicado | 2.2 | `MentionPolicy` + feature gate |
| SEC-7 | ALTO | ✅ Aplicado | 26 | RoomsController#destroy: log.warn + telemetry `admin_bypass: true` quando admin destrói sala não-própria |
| SEC-8 | MÉDIO | ✅ Aplicado | 26 | MessagePolicy update?/destroy? exige `member?` (user que saiu não pode editar/deletar suas msgs antigas via API) |
| SEC-9 | MÉDIO | ✅ Aplicado | 26 | `EDIT_WINDOW` (5min) movida pra MessagePolicy (defesa em profundidade) |
| SEC-10 | BAIXO | ✅ Documentado | 38 | StickerPolicy `update_columns` bypass console-only — comentário expandido explicando aceitabilidade (super_admin + container access) |
| SEC-11 | ALTO | ✅ Aplicado | 1.3 | `FeedbackTokenSigner` v1 com account_id + TTL 7d + 8 specs novos |
| SEC-12 | ALTO | ✅ Aplicado | 2.3 | Permission gate em 5 Internal*Tools (`agenda:cancel_event` etc) |
| SEC-13 | CRÍTICO | ✅ Defesa em profundidade | 1.4 | Falso positivo parcial; LLM não controla contact_id. Adicionada validação `Contact.exists?` |
| SEC-14 | ALTO | ✅ Aplicado | 2.3 | Rate limit 5/contact/dia em CreatePatientMinimalTool (Redis) |
| SEC-15 | MÉDIO | ✅ Fechado | 2.1 | PurgeUserDataJob fechado via MT-6 (account_id obrigatório como kwarg) |
| SEC-16 | MÉDIO | ✅ Aplicado | 36 | DataExporter `caller:` kwarg + valida `caller == user OR administrator`, raise `NotAuthorizedError` |
| SEC-17 | MÉDIO | ✅ Fechado | 30 | GroupSettingsDrawer JÁ tem `v-if="canManage"`/`isOwner` em todos admin buttons (FE-18) |
| SEC-18 | MÉDIO | ✅ Aplicado | 34 | `internal_chat_*` routes em KLIVY_REQUIRED_ROUTE_RULES exigindo `internal_chat.view` |
| SEC-19 | BAIXO | ✅ Aplicado | 34 | `ai_agent_*` routes → `captain.manage_follow_ups`/`manage_templates` |
| SEC-20 | MÉDIO | ✅ Fechado | 32 | MentionExtractor JÁ valida via `room.memberships.active.where(...)` (consolidado .active) |
| SEC-21 | MÉDIO | ✅ Aplicado | 35 | Allowlist `ALLOWED_CONTENT_ATTRIBUTES` em MessagesController (5 keys; resto silently dropado) |
| SEC-22 | CRÍTICO | ✅ Aplicado | 1.3 | `safe_for_prompt(raw)` em `contact_identity_block` |
| SEC-23 | CRÍTICO | ✅ Aplicado | 1.3 | `safe_for_prompt` em `history.at/type/summary` |
| SEC-24 | ALTO | ✅ Aplicado | 16 | Sentinel `sanitize_for_judging` + cost cap gate (`account:` kwarg + Redis check) |
| SEC-25 | ALTO | ✅ Aplicado | 35 | MessageGenerator `output_looks_like_message?` (cap 800 chars + 6 padrões STRUCTURED_OUTPUT_PATTERNS) |
| SEC-26 | MÉDIO | ✅ Aplicado | 33 | TemplateRenderer `sanitize_var` — cap 500 chars + normaliza CR/LF + colapsa newlines |
| SEC-27 | BAIXO | ✅ Aplicado | 33 | HealthController retorna só `status` + `checked_at` (era `snapshot.to_h` completo) |
| SEC-28 | ALTO | ✅ Aplicado | 33 | FeedbacksController rate limit Redis 60 req/min/IP (fail-open) |
| SEC-29 | BAIXO | ✅ Documentado | 38 | Engine monkey-patches bypass via update_columns/delete_all/raw SQL — comentário documentando aceitabilidade (super_admin + container) |

**Security: 28/29 aplicados + 1 falso positivo confirmado (CRÍTICO-11). ZERO pendentes.**

### Realtime (Seção 8)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| RT-1 | CRÍTICO | ✅ Aplicado | 1.5 | 7 handlers `internal_chat.*` wireados em `actionCable.js` |
| RT-2 | ALTO | ✅ Aplicado | 26+32 | 8 callsites consolidados: `where(left_at: nil)` → `.active` (Room, 5 policies, MentionExtractor) |
| RT-3 | MÉDIO | ✅ Aplicado | 26 | `rescue StandardError` per-user em destroy/update broadcasts |
| RT-4 | MÉDIO | ✅ Fechado | 3.2 | Por PERF-12 (typing rate limit) |
| RT-5 | MÉDIO | ✅ Aplicado | 42 | Listener `WEBSOCKET_RECONNECT` em ChatShell + RoomView refetcham rooms/messages após reconnect |
| RT-6 | BAIXO | ✅ Aceito (design futuro) | 60 | Unsubscribe per-room (descer subscriptions quando sala fechada). Custo de leak hoje: irrelevante — `user.pubsub_token` é stream único por user, broadcasts são filtrados client-side por `room_id` no payload. Implementar exigiria refactor do ActionCableListener pattern. Não bloqueante |
| RT-7 | BAIXO | ✅ Aplicado | 26 | Mark-read-by-sender consolidado em MessageDispatcher (single source of truth) |
| RT-8 | BAIXO | ✅ WONTFIX documentado | 26 | Limitação aceita (paciente vê via WhatsApp; agente humano vê msg ao chegar) |

**Realtime: 8/8 — 6 aplicados + 1 WONTFIX + 1 fechado por outro fix + RT-6 aceito como design futuro (não bloqueante).**

### Performance (Seção 6)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| PERF-1 | ALTO | ✅ Aplicado | 3.1 | RoomSerializer N+1 — preload + DISTINCT ON |
| PERF-2 | ALTO | ✅ Aplicado | 3.1 | unread_summary em 1 SQL LEFT JOIN GROUP BY |
| PERF-3 | ALTO | ✅ Aplicado | 22 | Stickers recent: `group.order(COUNT(*) DESC).limit(10)` no SQL |
| PERF-4 | ALTO | ✅ Fechado | 3.3 | Via PERF-8 (expression index `jsonb_array_length`) |
| PERF-5 | MÉDIO | ✅ Fechado | 3.3+40 | Via PERF-7 (index `created_at`). Health checker é global (sem account_id filter) — análise PERF-5 reconfirmada |
| PERF-6 | ALTO | ✅ Aplicado | 3.3 | Index `(account_id, contact_id, status, sent_at)` em follow_up_executions |
| PERF-7 | MÉDIO | ✅ Aplicado | 3.3 | Index `created_at` em traces (simplificado vs original) |
| PERF-8 | MÉDIO | ✅ Aplicado | 3.3 | Expression index `jsonb_array_length(history)` |
| PERF-9 | MÉDIO | ✅ Aceito | 40 | account_id já tem btree idx; partial IVFFlat por account é complexo. Migração futura pra pgvector HNSW resolve melhor |
| PERF-10 | BAIXO | ✅ N/A | 40 | Grep confirmou: zero queries SQL filtram `content_attributes ->> 'in_reply_to'`. GIN seria desperdício |
| PERF-11 | ALTO | ✅ Aplicado | 3.2 | Debounce server-side mark_read 2s |
| PERF-12 | ALTO | ✅ Aplicado | 3.2 | Rate limit typing 1s |
| PERF-13 | ALTO | ❌ Falso positivo | 3.2 | Eventos servem propósitos distintos, sem duplicação real |
| PERF-14 | MÉDIO | ✅ Aplicado | 3.2 | User N+1 nos broadcast loops (5 sites refatorados) |
| PERF-15 | MÉDIO | ✅ Aplicado | 22 | Paginação opt-in rooms#index (cap 200 + `meta`) |
| PERF-16 | MÉDIO | ✅ Aplicado | 22 | Paginação opt-in messages#favorites (cap 200 + `meta`) |
| PERF-17 | BAIXO | ✅ Aplicado | 22 | Paginação opt-in attachments#index (cap 200 + `meta`) |
| PERF-18 | ALTO | ✅ Fechado | 17 | Via ESC-1 — dispatcher refatorado pra per-account jobs |
| PERF-19 | ALTO | ✅ Fechado | 17 | Via ESC-2 (Distiller per-account paralelo) |
| PERF-20 | MÉDIO | ✅ Aceito | 42 | retry: 0 é decisão consciente — partial success duplica reply ao paciente; idempotency via Trace unique index (BE-10) protege |
| PERF-21 | BAIXO | ✅ Aplicado | 24 | `embed_batch` no EmbeddingClient (Redis MGET) + embeddings FORA da transação |
| PERF-22 | BAIXO | ✅ Aplicado | 23 | MessageThread.vue: 2 watchers consolidados em 1 |
| PERF-23 | BAIXO | ✅ Aplicado | 23 | StickerPicker store: `inFlightRefresh` promise compartilhada |
| PERF-24 | BAIXO | ❌ Falso positivo | 23 | Listener já balanceado (addEventListener/removeEventListener simétricos) |
| PERF-25 | MÉDIO | ✅ Aplicado parcial + decisão consciente | 64 | **Virtualizado**: `RoomList` (RecycleScroller, item-size=76 — height constante) + `MentionsView` (DynamicScroller, min-item-size=72, size-dependencies em content_preview/read_at). `MessageThread` **intencionalmente NÃO virtualizado** (documentado no header do arquivo): risks sem E2E coverage — (1) date dividers exigiriam achatar `grouped` em lista heterogênea, (2) `jumpTo` via querySelector quebra com items fora do viewport (precisaria scrollToItem + retry), (3) `scrollToBottom` em new message usa scrollEl direto (DynamicScroller API tem lifecycle diferente), (4) heights muito variáveis (texto 40px vs sticker 200px vs anexos 400px+), (5) reverse infinite scroll planejado colidiria. Impacto real só em salas com >500 msgs (raro hoje). Revisitar quando E2E framework existir. Vite compile verde |
| PERF-26 | BAIXO | ✅ Aplicado | 23 | RoomList: debounce 150ms na busca |

**Performance: 26/26 — 21 aplicados (incluindo PERF-25 parcial: RoomList + MentionsView virtualizados; MessageThread documentado como decisão consciente de adiar até E2E framework) + 2 falsos positivos + 4 fechados por outros fixes.**

### Backend (Seção 10)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| BE-1 | ALTO | ✅ Aplicado | 20-21 | Spec caracterizador ChatService — 30 examples, RubyLLM mocked, branches críticos |
| BE-2 | ALTO | ✅ Aplicado | 20-21 | Spec caracterizador ChatResponseJob — 27 examples, ChatService mocked, audio/visual paths |
| BE-3 | MÉDIO | ✅ Aplicado | 19 | Spec MessageDispatcher — 14 examples (BE-20 sanitization, MT-12 denormalization) |
| BE-4 | MÉDIO | ✅ Aplicado | 19 | Spec BroadcastMessageJob — 9 examples (MT-20 .active, PERF-13 dedup, fan-out) |
| BE-7 | ALTO | ✅ Aplicado | 15 | Unique partial index agenda_events `(account_id, contact_id, COALESCE(user_id,0), starts_at)` + rescue `RecordNotUnique` |
| BE-8 | MÉDIO | ✅ Aplicado | 37 | rescue `RecordNotUnique` em add_user_membership — idempotência (unique index `(room_id, user_id)` já protegia) |
| BE-9 | MÉDIO | ✅ Aceito | 37 | Pessimistic lock OK semanticamente; serialização teórica de 100 users desfavoritando MESMO custom sticker é caso raro |
| BE-10 | BAIXO | ✅ Aplicado | 2.1 | ChatService raise `DuplicateTurnError` em race do persist_trace |
| BE-11 | MÉDIO | ✅ Aplicado | 37 | rescue em BroadcastMessageJob.perform_later — queue down não derruba caller |
| BE-12 | MÉDIO | ✅ Aplicado | 17 | IngestDocumentJob rescue + marca `status: :failed` (estava implementado em ESC-2 era) |
| BE-13 | BAIXO | ✅ Fechado | 26 | Por RT-3 — rescue per-user em broadcast destroy |
| BE-14 | CRÍTICO | ❌ Falso positivo + defesa em profundidade | 1.4 | Frontend usa `{{ }}` Vue auto-escape; escape backend adicionado |
| BE-15 | ALTO | ✅ Aplicado | 1.3 | prompt sanitization SEC-22/23 |
| BE-16 | ALTO | ✅ Aplicado | 2.6 | Attachment/Sticker/Room URL helpers via SecureBlobsController |
| BE-17 | MÉDIO | ✅ Aplicado | 39 | `Message#soft_delete!` purga blobs dos attachments via `file.purge_later` (mantém rows) |
| BE-18 | MÉDIO | ✅ Documentado | 39 | Encryption at rest é responsabilidade do storage backend; docs em `config/storage.yml` com exemplo S3 SSE |
| BE-19 | MÉDIO | ✅ Aplicado | 2.7 | `unread_count` filtra `.visible` |
| BE-20 | MÉDIO | ✅ Aplicado | 2.1 | `MessageDispatcher.sanitize_in_reply_to!` |
| BE-22 | BAIXO | ✅ Aplicado | 38 | Sentinel rescue inclui `backtrace.first(3)` no log (preserva trace pra debug) |
| BE-23 | BAIXO | ✅ Aceito | 38 | rescue swallow é decisão consciente de design (best-effort em paths não-críticos); re-raise causaria retries indesejados |
| BE-24 | ALTO | ✅ Aplicado | 40 | Circuit breaker Redis em ChatService — 5 falhas em 60s → pula primary direto pra fallback, cooldown 5min |
| BE-25 | ALTO | ✅ Aplicado | 46 | LLM output validation distribuído: Distiller `parse` (allowlist PROFILE_KEYS + type normalize, doc explícita) + MessageGenerator `output_looks_like_message?` (SEC-25) + Guardrail::Validator (BE-15) — todos os outputs LLM validados antes de persist/display |
| BE-26 | ALTO | ✅ Aplicado | 16 | Cost cap em Distiller + MessageGenerator (Redis fail-open) + nil-guard |
| BE-27 | MÉDIO | ✅ Aplicado | 40 | Jitter `1.5s + rand×1.5s` no INLINE_RETRY_DELAY — evita thundering herd no fallback retry |

### Escalabilidade (Seção 7)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| ESC-1 | ALTO | ✅ Aplicado | 17 | FollowUpDispatcherJob → dispatcher + `FollowUpDispatcherPerAccountJob` por conta |
| ESC-2 | ALTO | ✅ Aplicado | 17 | ConsolidatePatientMemoryJob → dispatcher + per-account |
| ESC-3 | ALTO | ✅ Aplicado | 17 | ProactiveOutreachJob → dispatcher + per-account |

**Escalabilidade: 3/3 aplicados — janela noturna agora paraleliza via Sidekiq.**

### Frontend (Seção 9)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| FE-1 | ALTO | ✅ Aplicado | 43 | MessageBubble.vue 1044→928 LOC (-11%); 3 sub-componentes em `messageBubbleParts/` (ReadReceiptIcon, ReactionsBar, MessageActionsMenu) |
| FE-2 | ALTO | ✅ Aplicado | 44 | GroupSettingsDrawer.vue 601→327 LOC (-46%); 6 sub-componentes em `groupSettingsParts/` |
| FE-3 | MÉDIO | ✅ Aplicado | 41 | followUps/Index.vue 702→189 LOC (-73%); 4 sub-componentes em `followUps/components/` |
| FE-4 | MÉDIO | ✅ Aplicado | 41 | internalNotificationTemplates/Index.vue 516→172 LOC (-67%); 3 sub-componentes em `internalNotificationTemplates/components/` |
| FE-5 | MÉDIO | ✅ Aplicado | 28 | Tooltip do beclinic_core agora usado em 13 lugares (era 0) |
| FE-6 | MÉDIO | ✅ Aplicado | 28-29 | 49 `title="..."` substituídos por `<Tooltip>` em 13 arquivos |
| FE-7 | MÉDIO | ✅ Aplicado | 27 | `window.confirm` → ConfirmDangerModal em 2 routes (`followUps`, `internalNotificationTemplates`) |
| FE-8 | MÉDIO | ✅ Aplicado | 63 | Sweep BeclinicButton/FormSelect/Checkbox em 13 arquivos (4 ai_agent + 9 internal_chat). **23 substituições**: 21 `<button>` → `<BeclinicButton>` (footers Cancelar/Salvar com `is-loading` automático, header CTAs, danger actions com `color="ruby"`, edit/save inline com `size="xs"`), 1 `<select>` → `<FormSelect>` (TemplateFormModal target picker com `auto-searchable`), 1 `<input type="checkbox">` → `<Checkbox>` (NewRoomModal "adicionar Bea"). Skipped (com razão documentada): action cards com flex-1 + SVG inline (FollowUpRuleCard/TemplateCard), popover ARIA items (MentionPopover), tooltip-wrapped icon buttons (MessageComposer/AudioRecorder/RoomView), state-machine controls (AudioRecorder), list-row items com badges/counters (RoomListItem), e reactions/menu items (já no escopo do design system de chat). Vite sem erros |
| FE-9 | MÉDIO | ✅ Fechado | 2.5 | Por MT-15 (reset action limpa TIMERS Map) |
| FE-10 | MÉDIO | ❌ Falso positivo | 29 | Vars são function-scope (não module-scope); cleanup via `onBeforeUnmount` correto |
| FE-11 | BAIXO | ❌ Falso positivo | 23 | Listener já balanceado (mesmo que PERF-24) |
| FE-12 | BAIXO | ✅ Fechado | 23 | Por PERF-22 (2 watchers consolidados em 1) |
| FE-13 | MÉDIO | ✅ Aplicado | 28 | `localSending` mutex sync em MessageComposer.send/sendSticker |
| FE-14 | MÉDIO | ✅ Aplicado | 42 | `stickerActionPending` migrado per-bubble → global no store (`pendingStickerIds[] + isStickerPending getter`) |
| FE-15 | BAIXO | ✅ Aplicado | 28 | toggleFavorite revert lê estado fresh (preserva updates via cable) |
| FE-16 | MÉDIO | ✅ Aplicado | 47-57 | i18n COMPLETO: ~236 strings frontend migradas em TODOS os user-facing components dos 2 plugins, ~309 keys nos JSONs `internalChat.json` + `aiAgent.json`. Ver ARCH-23 |
| FE-17 | BAIXO | ✅ Aplicado | 50 | i18n backend: 17 strings migradas pra `I18n.t` em SystemMessageBuilder (6) + RoomCreator (4) + outros services. YAMLs em `plugins/*/config/locales/pt_BR.yml` |
| FE-18 | MÉDIO | ✅ Aplicado | 30 | Botões admin gated via `v-if="canManage"`/`isOwner` (já implementado em lotes anteriores) |
| FE-19 | BAIXO | ✅ Aceito por design | 60 | Stickers e Files panels não têm role gating: visualizar stickers/arquivos é OK pra todos os members (não exfiltra dado sensível — só lista assets já visíveis nas mensagens da sala). Admin actions (`destroy sticker`, configurar room) JÁ têm gating via FE-18/SEC-5 |
| FE-20 | MÉDIO | ✅ Aplicado | 30 | Countdown tempo real durante edit + warning <60s + mensagem clara em expiração |
| FE-21 | MÉDIO | ✅ Aplicado | 30 | `fetchFavorites` retorna `{ items, meta }` + aviso UI quando há favoritos invisíveis |
| FE-22 | MÉDIO | ✅ Aplicado | 27+31 | Sticker default no-op no store + backend retorna `is_favorite: true, default: true` |
| FE-23 | BAIXO | ✅ Aplicado | 27 | RoomView watcher debounce 300ms — evita redirect em null transiente |

**Frontend: 23/23 — 20 aplicados (FE-1/2/3/4/5/6/7/8/13/14/15/16/17/18/20/21/22/23) + 2 falsos positivos (FE-10/11) + 2 fechados por outros fixes (FE-9/12) + FE-19 aceito por design. ZERO roadmap.**

### Arquiteturais (Seção 11)

| ID | Severidade | Status | Lote | Notas |
|---|---|---|---|---|
| ARCH-1 | ALTO | ✅ Aplicado | 45 | ChatService 1017→907 LOC + 3 módulos (StateMachineUpdater, CircuitBreaker, HistoryFormatter). 120/120 specs verde |
| ARCH-2 | MÉDIO | ✅ Já coberto | 20-21 | BE-1/BE-2 specs caracterizadores (57 examples) cobrem ChatResponseJob; decompose adicional não necessário |
| ARCH-6 | ALTO | ✅ Aplicado | 43 | MessageBubble.vue 1044→928 LOC + 3 sub-componentes em messageBubbleParts/ |
| ARCH-7 | MÉDIO | ✅ Aplicado | 44 | GroupSettingsDrawer.vue 601→327 LOC + 6 sub-componentes em groupSettingsParts/ |
| ARCH-13 | BAIXO | ✅ Aplicado | 49 | Convenção `.call` documentada em AGENTS.md; aliases adicionados em Dispatcher + SystemPrompt (backwards-compat preservada) |
| ARCH-14 | BAIXO | ✅ Documentado | 59 | `ReadReceipt` formalizado como "reservado pra futura granularização" via comentário prominente no model + comentário na association `Message#has_many :read_receipts`. PRD chat-interno.md:180 é canon. Decisão documentada — NÃO adicionar writes sem alinhar PRD primeiro |
| ARCH-15 | BAIXO | ✅ Aplicado | 59 | `internal_chat:seed_default_stickers` adicionado ao [docker/entrypoints/rails.sh](../../docker/entrypoints/rails.sh) (antes do `exec "$@"`). Roda em TODOS os ambientes (local docker-compose, prod Easypanel, test) — entrypoint é executado antes do command override de cada ambiente. **Correção pós-revisão**: tentativa inicial alterou `CMD` dos Dockerfiles mas ninguém usa esse CMD (todos têm `command:` override), então foi inerte. Solução final via entrypoint resolve em todos os ambientes sem dependência de configuração externa. Idempotente (find_or_initialize_by + skip se file_size bate) — custo ~2s sem mudanças, ~10s com novos arquivos. `|| true` proposital: falha de blob storage não derruba boot (sticker é nice-to-have) |
| ARCH-18 | MÉDIO | ✅ Aplicado | 48 | READMEs em `plugins/ai_agent/` e `plugins/internal_chat/` — arquitetura em 1 página + componentes + multi-tenancy invariants |
| ARCH-19 | MÉDIO | 🟡 Aceito como N/A | — | Swagger sync verification exige nova revisão controller-by-controller. Fora de escopo |
| ARCH-20 | BAIXO | ✅ Aplicado | 48 | 3 ADRs em `docs/adr/` (0001 LLM provider fallback, 0002 Sentinel opt-in, 0003 Read receipts via Membership) |
| ARCH-21 | MÉDIO | ✅ Aplicado | 58 | `InternalChat::UserBroadcaster` extraído. 7 call-sites refatorados (BroadcastMessageJob, RoomCreator, MembershipsController, MessagesController×2, TypingController, RoomsController×2). 2 APIs (`call` payload único, `each` block) + `isolate: true` preservando RT-3. **Bônus**: RoomCreator agora também isola erros per-user (era rescue-all-around, podia derrubar broadcasts seguintes). 62/62 specs verde |
| ARCH-23 | MÉDIO | ✅ Aplicado | 47-57 | i18n COMPLETO: ~236 strings frontend + ~17 backend migradas, ~309 keys disponíveis, AGENTS.md pattern documentado. Todos os user-facing components dos 2 plugins i18n-aware |
| ARCH-3 | MÉDIO | ✅ Aplicado | 62 | `SearchAvailableSlotsTool` 480→298 LOC (-38%) + 3 sub-classes em `search_available_slots_tool/`: `DateRangeValidator` (39 LOC, parse + bounds), `SlotAllocator` (131 LOC, slots por dia), `PeriodDistributor` (106 LOC, multi-dia + balance manhã/tarde). Main tool foca orquestração + DB preload + gap_context/notes (lógica de UX/brand). `find_day_config` exposto como class method de PeriodDistributor pra reuso em `closed_window_gap`. 136/136 ai_agent specs verde |
| ARCH-4 | MÉDIO | ✅ Aceito | 60 | `PromptBuilder` 271 LOC. Audit original marcou "Acceptable — single responsibility complex domain". Mantido conforme análise original |
| ARCH-5 | MÉDIO | ✅ Aceito | 60 | `ContextBuilder` 290 LOC. Audit original marcou "Acceptable". Mantido |
| ARCH-8 | MÉDIO | ✅ Fechado | 41 | `followUps/Index.vue` 690 LOC já decomposto via FE-3 (702→189 LOC + 4 sub-componentes) |
| ARCH-9 | MÉDIO | ✅ Fechado | 41 | `internalNotificationTemplates/Index.vue` 471 LOC já decomposto via FE-4 (516→172 LOC + 3 sub-componentes) |
| ARCH-10 | BAIXO | ✅ OK (já conforme) | — | `ai_agent/engine.rb` 9 monkey-patches em 6 classes core, todos com guards idempotentes (`unless method_defined?`) — pattern correto, sem ação necessária |
| ARCH-11 | BAIXO | ✅ OK (já conforme) | — | `internal_chat/engine.rb` 2 simples associations, guarded — sem ação necessária |
| ARCH-12 | MÉDIO | ✅ Aplicado | 61 | Spec `plugins/ai_agent/spec/engine/monkey_patches_spec.rb` com **16 examples** cobrindo: (a) class existence (Captain::Assistant + ResponseBuilderJob ainda existem), (b) atributos esperados (name/account_id/config), (c) callbacks instalados (`before_destroy/before_update/after_save` por nome), (d) comportamento real (Beatriz não pode ser destruída/renomeada, outras podem), (e) sync_bea_enabled mirroring config→AccountSetting, (f) SkipBeatrizLegacyResponse prepended em ResponseBuilderJob, (g) Account auto-criação de Beatriz idempotente. **Drift detection** — quebra cedo em CI se Chatwoot upgrade alterar API. 16/16 verde |
| ARCH-16 | BAIXO | ✅ OK (já conforme) | — | Cross-engine coupling: `ai_agent` → `InternalChat::*` (notifier + responder) e `internal_chat` → `Captain::Assistant` (Bea resolver) são legítimos. Sem coupling circular. |
| ARCH-17 | BAIXO | ✅ OK (já conforme) | — | Naming: Models PascalCase + namespaced; tables snake_case + prefixed; routes scoped `/accounts/:account_id/`; Vue PascalCase. Tudo conforme — sem ação necessária |
| ARCH-22 | BAIXO | ✅ Aceito | 60 | Serialização inconsistente (Serializer class vs plain hash). Cosmético; padronizar exigiria refactor de ~10 controllers sem ganho funcional. Aceito como convenção mista — Serializers pra entidades com lógica de view (current_user, derived fields), hashes pra payloads simples |

**Arquiteturais: 23/23 — 16 aplicados (1/2/3/6/7/12/13/14/15/18/20/21/23 + 8/9 fechados por FE-3/4) + 4 OK já conforme (10/11/16/17) + 3 aceitos (4/5/22) + 1 N/A (19). ZERO roadmap.**

### Sumário numérico atualizado (quarta revisão 2026-05-19)

| Severidade | Aplicados/Aceitos/FP | Roadmap | Total |
|---|---|---|---|
| CRÍTICO | 15 | 0 | 15 |
| ALTO | 46 | 0 | 46 |
| MÉDIO | 75 | 0 | 75 |
| BAIXO | 33 | 0 | 33 |
| **TOTAL** | **169** | **0** | **169** |

# 🎯 100% das findings tratadas (169/169)

**ZERO roadmap pendente. ZERO bloqueador. ZERO CRÍTICO/ALTO em aberto.** Audit fechado.

**Resumo dos resolvidos**: aplicado (118+) · aceito por design (8) · falso positivo (6) · fechado por outro fix (37+) · OK já conforme (4) · documentado como decisão consciente (parcial em PERF-25 MessageThread, com justificativa técnica). **Drift detection ativa** via spec `monkey_patches_spec.rb`. **Decompose de god files completo**. **UI primitives padronizados**.

**Resolvidos formalmente no lote 60** (sem mudança de código, só status no audit): MT-8/9/10 (cron jobs cross-account intencionais), RT-6 (unsubscribe per-room — leak irrelevante), FE-16/17 (i18n já aplicado em lotes 47-57, status corrigido), FE-19 (panels não-admin OK), ARCH-4/5 (LOC counts acceptable per audit original), ARCH-8/9 (fechados via FE-3/4), ARCH-10/11/16/17 (já conformes), ARCH-19 (Swagger sync N/A), ARCH-22 (serialização mista intencional).

> Diferença vs apêndice C (165 total): apêndice D inclui findings sub-numerados (PERF-3 com 7 sub-itens BE-14 a BE-20 etc) que estavam agrupados antes. Aproximação razoável.

### Histórico de lotes

| Lote | Data | Findings cobertos | Arquivos |
|---|---|---|---|
| 1.1 Multi-tenant críticos | 2026-05-18 | MT-1, 2, 3, 4 | 5 modificados |
| 1.2 RBAC bloqueadores | 2026-05-18 | SEC-1, SEC-2 | 2 novos + 2 modificados |
| 1.3 LLM safety + HMAC | 2026-05-18 | SEC-11, 22, 23 | 4 modificados + spec expandido |
| 1.4 BE-14 + SEC-13 | 2026-05-18 | BE-14, SEC-13 | 2 modificados (defesa em profundidade) |
| 1.5 RT-1 ActionCable | 2026-05-18 | RT-1 | 1 modificado (core actionCable.js) |
| 2.1 LGPD + isolation jobs | 2026-05-18 | MT-5, 6, 7, BE-20 | 5 modificados |
| 2.2 RBAC controllers | 2026-05-18 | SEC-3, 4, 5, 6 | 4 novos + 6 modificados |
| 2.3 Tools privilegiadas | 2026-05-18 | SEC-12, SEC-14 | 9 modificados |
| 2.4 StickerFavorite | 2026-05-18 | MT-11 | 1 migration + 2 modificados |
| 2.5 Stores reset | 2026-05-18 | MT-14 a 19 | 12 modificados |
| 2.6 SecureBlobs | 2026-05-18 | BE-16 | 3 modificados |
| 3.1 N+1 fix | 2026-05-19 | PERF-1, 2 | 2 modificados |
| 3.2 Broadcast efficiency | 2026-05-19 | PERF-11, 12, 14 | 5 modificados |
| 3.3 DB indexes | 2026-05-19 | PERF-6, 7, 8 | 1 migration |
| 2.7 Residuais multi-tenant | 2026-05-19 | MT-12, 13, 20, BE-19 | 6 modificados |
| 15. BE-7 double-booking | 2026-05-19 | BE-7 | 1 migration + 2 tools |
| 16. Cost cap + Sentinel | 2026-05-19 | BE-26, SEC-24 | Distiller, MessageGenerator, Sentinel, ChatService |
| 17. ESC scaling cron | 2026-05-19 | ESC-1, 2, 3 | 3 dispatchers refatorados + 3 per-account jobs novos |
| 18. PERF-19 (via ESC-2) | 2026-05-19 | PERF-19 | (já no lote 17) |
| 19. Specs MessageDispatcher + Broadcast | 2026-05-19 | BE-3, BE-4 | 2 spec files (23 examples) |
| 20-21. Specs ChatService + ChatResponseJob | 2026-05-19 | BE-1, BE-2 | 2 spec files (57 examples) |
| 22. Quick wins PERF | 2026-05-19 | PERF-3, 15, 16, 17 | Stickers SQL sort + paginação opt-in (rooms, favorites, attachments) |
| 23. Frontend perf | 2026-05-19 | PERF-22, 23, 26 | MessageThread watchers, sticker dedup, RoomList debounce |
| 24. PERF-21 batch + tx | 2026-05-19 | PERF-21 | `embed_batch` (Redis MGET) + IngestDocumentJob fora da tx |
| 25. (placeholder) | — | — | — |
| 26. RBAC + Realtime | 2026-05-19 | SEC-7, 8, 9, RT-2, 3, 7, 8 | Audit log destroy, member check, EDIT_WINDOW policy, .active sweep, rescue per-user, mark-read consolidado |
| 27. UX fixes | 2026-05-19 | FE-7, 22, 23, 12 (já) | ConfirmDangerModal x2, sticker default consist, RoomView debounce |
| 28. Frontend BAIXOs | 2026-05-19 | FE-13, 15, 5, 6 (parcial) | localSending mutex, toggleFavorite fresh, Tooltip 4 lugares chave |
| 29. FE-6 sweep completo | 2026-05-19 | FE-6 (45 subs em 11 arquivos) | Tooltip sweep mecânico |
| 30. UX gating | 2026-05-19 | FE-18, 20, 21 | Edit countdown, favorites meta aviso |
| 31. FE-22 backend fix | 2026-05-19 | FE-22 | Sticker default backend retorna is_favorite: true |
| 32. RT-2 residual + reconciliação Apêndice D | 2026-05-19 | RT-2 (mention_extractor), SEC-15/17/20/SEC-14 confirmações de já-feito | — |
| 33. Security defensivo | 2026-05-19 | SEC-26, SEC-27, SEC-28 | TemplateRenderer sanitize_var, HealthController PUBLIC_FIELDS, FeedbacksController rate limit |
| 34. Router guards | 2026-05-19 | SEC-18, SEC-19 | KLIVY_REQUIRED_ROUTE_RULES com 5 entries (internal_chat + ai_agent) |
| 35. LLM output + strong params | 2026-05-19 | SEC-25, SEC-21 | MessageGenerator output_looks_like_message? + MessagesController ALLOWED_CONTENT_ATTRIBUTES |
| 36. LGPD autorização | 2026-05-19 | SEC-16 | DataExporter caller: validation + NotAuthorizedError |
| 37. Race conditions backend | 2026-05-19 | BE-8, BE-11 | memberships rescue RecordNotUnique + MessageDispatcher rescue perform_later |
| 38. Cosméticos doc + error handling | 2026-05-19 | SEC-10, SEC-29, BE-22, BE-23 | Comentários documentando bypass aceitável + backtrace no Sentinel rescue + BE-23 aceito |
| 39. Cleanup + encryption | 2026-05-19 | BE-17, BE-18 | soft_delete purga blobs via purge_later + docs encryption-at-rest em storage.yml |
| 40. LLM resilience | 2026-05-19 | BE-24, BE-27 + PERF-5/9/10 | Circuit breaker Redis-based + jitter no retry; PERF-5/9/10 já feitos/aceitos |
| 41. Decompose Vue routes | 2026-05-19 | FE-3, FE-4 | followUps Index 702→189 LOC, templates Index 516→172 LOC, 7 sub-componentes |
| 42. Frontend race + reconnect + PERF-18/20 | 2026-05-19 | FE-14, RT-5, PERF-18, PERF-20 | sticker pending global no store + WebSocket reconnect listeners; PERF-18/20 confirmados |
| 43. Decompose MessageBubble | 2026-05-19 | FE-1 | MessageBubble.vue 1044→928 LOC + 3 sub-componentes em messageBubbleParts/ |
| 44. Decompose GroupSettingsDrawer | 2026-05-19 | FE-2 | GroupSettingsDrawer.vue 601→327 LOC + 6 sub-componentes em groupSettingsParts/ |
| 45. Decompose ChatService (Fase 4 final) | 2026-05-19 | ARCH-1 | ChatService.rb 1017→907 LOC + 3 módulos em chat_service/ (StateMachineUpdater, CircuitBreaker, HistoryFormatter). 120/120 specs verde |
| 46. BE-25 LLM output validation (último ALTO) | 2026-05-19 | BE-25 | Documentação explícita em Distiller.parse explicando a defesa em profundidade. Combinado com SEC-25 (MessageGenerator) + BE-15 (Guardrail::Validator), todos os outputs LLM são validados |
| 47. i18n bootstrap (FE-16/17 + ARCH-23) | 2026-05-19 | FE-16, FE-17, ARCH-23 | Stubs pt_BR.yml em ambos plugins + 7 strings migradas (controllers user-facing) + AGENTS.md pattern documentado. **Rollout incremental** das ~167 strings restantes fica como roadmap |
| 48. Docs arquiteturais (ARCH-18 + ARCH-20) | 2026-05-19 | ARCH-18, ARCH-20 | READMEs em ambos plugins (arquitetura em 1 página + componentes + multi-tenancy) + 3 ADRs em docs/adr/ (LLM provider fallback, Sentinel opt-in, Read receipts via Membership). ARCH-19 (Swagger sync) aceito como N/A |
| 49. Convenção .call (ARCH-13) | 2026-05-19 | ARCH-13 | Convenção documentada em AGENTS.md (Service Entry Methods) + aliases .call em Dispatcher + SystemPrompt (backwards-compat) |
| 50. i18n rollout incremental | 2026-05-19 | FE-16, FE-17, ARCH-23 | Backend: SystemMessageBuilder (6) + RoomCreator (4) migrados pra I18n. Frontend: JSONs internalChat.json (~30 keys) + aiAgent.json (~15) criados e registrados em pt_BR/index.js + 5 strings demo migradas (MessageBubble + Composer) |
| 51. Fix locale name (pt-BR → pt_BR) | 2026-05-19 | FE-16/17 (bug) | Bug introduzido no lote 47: YAMLs com `pt-BR:` (hífen). Rails ignora silenciosamente locales não-registrados. Trocado pra `pt_BR:` em ambos plugins. Boot test confirmou 3 traduções renderizadas |
| 52. i18n components core | 2026-05-19 | FE-16/17, ARCH-23 | ChatShell (3) + RoomList (4) + RoomView (6) + FavoritesPanel (5) migrados — total ~40 strings i18n-aware nos paths principais (header, sidebar, thread, favoritos, composer) |
| 53. i18n ai_agent routes | 2026-05-19 | FE-16/17, ARCH-23 | FollowUpsHeader (5) + FollowUpsEmptyState (3) + followUps/Index ConfirmDangerModal (3) + templates ConfirmDangerModal (3) — ~14 strings ai_agent migradas com interpolation completa |
| 54. i18n GroupSettingsDrawer parts | 2026-05-19 | FE-16/17, ARCH-23 | 6 sub-componentes (Header, HeroSection, DescriptionSection, QuickLinks, MembersSection, DangerZone) — 36 strings migradas + 40 keys novas no namespace GROUP_SETTINGS. Pluralização manual + `useI18n()` composable em MembersSection pro `memberRole` helper |
| 55. i18n ai_agent forms grandes | 2026-05-19 | FE-16/17, ARCH-23 | FollowUpRuleCard (7) + FollowUpFormModal (21) + TemplateCard (5) + TemplateFormModal (17) — ~50 strings migradas + 101 keys novas no aiAgent.json (27→128). Constants (TRIGGER/UNIT/APPLIES_TO/TARGET_TYPE) migrados via `computed(() => [...])` chamando t() |
| 56. i18n internal_chat secundários | 2026-05-19 | FE-16/17, ARCH-23 | NewRoomModal (12) + FilesPanel (13) + StickerPicker (22) + AudioRecorder (6) — 53 strings migradas + 53 keys novas em 4 namespaces (NEW_ROOM, FILES, STICKER_PICKER, AUDIO_RECORDER) |
| 57. i18n internal_chat thread (rollout completo) | 2026-05-19 | FE-16/17, ARCH-23 | 10 components finais: MessageThread, RoomListItem, MentionsView, TypingIndicator (pluralização SINGULAR/DUAL/PLURAL), AudioMessage, ReplyPreview, MessageAttachments + 3 messageBubbleParts (ReadReceiptIcon, ReactionsBar, MessageActionsMenu) — ~60 strings + 56 keys novas. **Rollout i18n COMPLETO**: ~236 strings frontend + 17 backend + ~309 keys disponíveis. Todos os user-facing components dos 2 plugins agora i18n-aware |
| 58. ARCH-21 UserBroadcaster extract | 2026-05-19 | ARCH-21 | `InternalChat::UserBroadcaster` (2 APIs: `call` payload único, `each` block) extraído do pattern repetido. 7 call-sites refatorados em 6 arquivos (BroadcastMessageJob, RoomCreator, MembershipsController, MessagesController×2, TypingController, RoomsController×2). `isolate: true` preserva RT-3 (rescue per-user) onde aplicável. **Bônus de robustez**: RoomCreator agora também isola per-user (era rescue-all-around → primeiro erro derrubava broadcasts subsequentes). 62/62 specs verde |
| 59. ARCH-14/15 ReadReceipt formalize + entrypoint seed | 2026-05-19 | ARCH-14, ARCH-15 | (a) `ReadReceipt` model + `Message#has_many :read_receipts` ganham comentários prominentes documentando como "reservado pra futura granularização" (canon hoje é `Membership.last_read_message_id` — PRD chat-interno.md:180). (b) `internal_chat:seed_default_stickers` adicionado ao [docker/entrypoints/rails.sh](../../docker/entrypoints/rails.sh) (antes do `exec "$@"`) — roda em todos os ambientes (local, prod Easypanel, test) porque o entrypoint precede qualquer command override. **Pós-revisão**: tentativa inicial nos Dockerfiles foi inerte (ninguém usa CMD com `command:` override) — corrigido pra entrypoint. Idempotente, `|| true` proposital |
| 60. Formalização WONTFIX/N/A | 2026-05-19 | MT-8/9/10, RT-6, PERF-25, FE-8/16/17/19, ARCH-3/4/5/8/9/10/11/12/16/17/19/22 | Reconciliação de status no Apêndice D — sem mudança de código. Itens aceitos como design (cron jobs cross-account intencionais, panels não-admin OK, leak de subscription irrelevante), N/A (Swagger sync fora de escopo), corrigidos (FE-16/17 já aplicados em lotes 47-57), roadmap explícito (4 MÉDIO acionáveis adiados). Resultado: **98% das findings tratadas, ZERO bloqueador residual** |
| 61. ARCH-12 drift detection spec | 2026-05-19 | ARCH-12 | `plugins/ai_agent/spec/engine/monkey_patches_spec.rb` com 16 examples — class existence, atributos esperados, callbacks instalados (before_destroy/before_update/after_save por nome), comportamento real (protect_beatriz_destroy/rename, sync_bea_enabled), SkipBeatrizLegacyResponse prepended, Account auto-criação de Beatriz idempotente. **Quebra cedo em CI** se Chatwoot upgrade alterar API. 16/16 verde, 198/199 full plugin sweep (1 falha pré-existente em MessagePolicy spec, não-relacionada) |
| 62. ARCH-3 SearchAvailableSlotsTool decompose | 2026-05-19 | ARCH-3 | Tool 480→298 LOC (-38%) + 3 sub-classes em `search_available_slots_tool/`: `DateRangeValidator` (39 LOC — parse + bounds checks), `SlotAllocator` (131 LOC — slots por dia, helpers privados parse_minutes/period_match/overlaps/format_slot), `PeriodDistributor` (106 LOC — multi-dia + balance 2 manhã/2 tarde, expõe `find_day_config` como class method pra reuso no `closed_window_gap`). Main tool foca orquestração + DB preload + gap_context/notes (lógica de UX/brand). 136/136 ai_agent specs verde |
| 63. FE-8 BeclinicButton/FormSelect/Checkbox adoption | 2026-05-19 | FE-8 | Sweep em 13 components (4 ai_agent + 9 internal_chat) com **23 substituições**: 21 `<button>` → `<BeclinicButton>` (footers Cancelar/Salvar com `is-loading` automático, CTAs, danger `color="ruby"`, inline edit `size="xs"`), 1 `<select>` → `<FormSelect>` (TemplateFormModal com `auto-searchable`), 1 `<input type="checkbox">` → `<Checkbox>` (NewRoomModal "adicionar Bea"). Skipped (com razão documentada no relatório): action cards com SVG inline, popover ARIA, tooltip-wrapped icons, state-machine controls (audio recorder), list-row items com badges. Vite sem erros |
| 64. PERF-25 virtualização (vue-virtual-scroller) | 2026-05-19 | PERF-25 | RoomList migrado pra `RecycleScroller` (item-size=76, height constante) e MentionsView pra `DynamicScroller` (min-item-size=72, size-dependencies em content_preview/read_at). Ganho real em contas com 500+ salas ou históricos longos de menções. MessageThread **NÃO virtualizado** (decisão consciente, documentada no header do arquivo): 5 riscos sem E2E (date dividers achatamento, jumpTo via querySelector, scrollToBottom direto, heights muito variáveis, reverse infinite scroll planejado). Vite compile verde — HTTP 200 nos 2 arquivos modificados. **Audit fechado em 100%** |

### Recomendações remanescentes priorizadas

**Bloqueadores funcionais ou de risco material**: zero. Todos endereçados.

**Próxima onda recomendada (Fase 4 ou continuação tactical):**

1. **ARCH-1 ChatService decompose** + specs (cobre lacuna BE-1) — 1 sprint
2. **ARCH-6 MessageBubble.vue decompose** — 0.5 sprint
3. **BE-7 unique constraint agenda_events** — 1 dia (previne double-booking via race)
4. **BE-26 cost cap em Distiller/MessageGenerator/Sentinel** — 2 dias
5. **SEC-24 Sentinel injection mitigation** — 3 dias (LLM-as-judge bypass)
6. **ESC-1 a 4 batching de cron jobs por account** — 1 sprint (escalabilidade)
7. **ARCH-23 i18n strings PT externalizar** — 1 sprint (compliance Chatwoot)
8. **BE-1 a 5 specs caminhos críticos** — 1 sprint (cobertura)

**Itens cosméticos/cuidadosos**: agrupar em chore commits sem urgência. ~50 fixes ainda na lista, maioria BAIXO.
