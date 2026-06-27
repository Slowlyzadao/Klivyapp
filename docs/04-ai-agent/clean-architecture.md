# Bea (AI Agent) — Arquitetura Limpa & Registro Cross-Boundary

> **Documento vivo.** Este é o contrato de governança do trabalho da Bea (plugin `ai_agent`).
> Toda mudança ou dependência que saia da pasta `plugins/ai_agent/` é registrada aqui — **sempre**.
> Mantido por: Claude (sob orientação do Leandro). Última atualização: **2026-06-09**.

---

## 0. Como usar este documento

- **Antes** de mexer em qualquer arquivo **fora** de `plugins/ai_agent/`, registre na seção [§3 Change Log](#3-registro-de-mudanças-cross-boundary-living-log).
- Toda **dependência** (leitura/uso) que a Bea tem de outro plugin ou do core vai em [§4 Mapa de Dependências](#4-mapa-de-dependências-externas-leituras).
- Todo **componente** Vue criado ou reutilizado vai em [§5 Registro de Componentes](#5-registro-de-componentes).
- Toda **decisão de produto** da Bea vai em [§6 Decisões](#6-decisões-de-produto-bea).

A regra mental: **a Bea prefere DEPENDER do que já existe a MODIFICAR o que está fora dela.**
Modificar fora de `ai_agent` é o último recurso — e quando acontece, é documentado.

---

## 1. Princípios invioláveis

1. **Tudo da Bea vive em `plugins/ai_agent/`.** Nova funcionalidade = novo arquivo dentro do plugin, espelhando a estrutura Rails (`app/models`, `app/services`, `app/jobs`, `app/controllers`, `app/policies`).
2. **Tools** ficam em `app/services/ai_agent/tools/`, herdam de `BaseTool`, e são registradas via:
   - uma **seed migration** em `plugins/ai_agent/db/migrate/` que cria o `AiAgent::ToolDefinition` (`key`, `description`, `enabled`);
   - o `AiAgent::ToolRegistry` (lookup por `key`).
3. **Namespacing — sempre qualificar constantes irmãs.** Em classes de estilo compacto (`class AiAgent::Foo`), o escopo léxico **não** inclui `AiAgent`. Referência nua a uma irmã (`GlobalSetting`) lança `NameError` em runtime.
   - ✅ `AiAgent::GlobalSetting.current`  ❌ `GlobalSetting.current`
   - *(Lição do bug `config_resolver.rb`, 2026-06-06.)*
4. **Cross-plugin é defensivo.** A Bea pode **ler** models de outros plugins, mas nunca assume schema:
   - `defined?(::AgendaService)` antes de usar; `obj.respond_to?(:price)` antes de chamar.
   - *(Lição do bug `prompt_builder.rb` → `s.price` numa tabela sem coluna `price`, 2026-06-06.)*
5. **Decisões críticas saem do prompt e viram código determinístico.** Invariantes de segurança/correção (emergência, menor de idade, "não agendar sem identidade confirmada", janela de busca) vivem em `chat_service`, `critique`, `state_machine` — **nunca** confiados só ao LLM. O prompt orquestra a conversa; o código garante o que não pode falhar.
6. **System prompt cacheável.** O texto estável (persona, fluxo) vai no system prompt (`CAPTAIN_BEA_SYSTEM_PROMPT`). O contexto por-turno (data/hora, status aberto/fechado, hints de fluxo) vai como **prefixo da mensagem do usuário** — nunca no system prompt — pra preservar cache-hit.
7. **Nada de editar o core sem aprovação + registro** neste documento.
8. **Registro de modelos do `ruby_llm` fica velho.** O gem valida o id do modelo contra um registro estático e levanta `ModelNotFoundError` para modelos lançados depois do release do gem (ex.: `gemini-3.5-flash` existe na API da Google, mas não no registro). Solução adotada (em `chat_service.rb`): `RubyLLM.chat(model:, provider:, assume_model_exists: true)` — vai direto pra API real. Assim qualquer modelo configurado funciona. *(Lição 2026-06-06.)*
9. **O core só injeta a credencial da OpenAI** (`lib/llm/config.rb` → `Llm::Config.initialize!`). O Gemini é provider da Bea, então o plugin injeta a própria key (`ChatService#wire_gemini_credentials!`, lê `CAPTAIN_GEMINI_API_KEY`). Sem isto → `RubyLLM::ConfigurationError: Missing configuration for Gemini`.

### Correções de runtime aplicadas (dentro de `ai_agent` — não cross-boundary)

> Bugs que só apareciam ao exercitar a Bea de verdade. Todos corrigidos em `plugins/ai_agent/`.

| Data | Arquivo | Bug | Fix |
|------|---------|-----|-----|
| 2026-06-06 | `config_resolver.rb` | refs nuas a constantes irmãs em classe compacta → `NameError` | qualificar `AiAgent::X` |
| 2026-06-06 | `prompt_builder.rb` | `s.price` em `AgendaService` sem coluna `price` → `NoMethodError` | guard `respond_to?(:price)` |
| 2026-06-06 | `chat_service.rb` | Gemini sem key + modelo fora do registro do gem | `wire_gemini_credentials!` + `assume_model_exists` |
| 2026-06-06 | `clinic_info_tool.rb` | associação morta `AgendaService#users` (renomeada p/ `professionals`) + `s.price` | `professionals` + guard de price |
| 2026-06-06 | `search_available_slots_tool.rb` | `service.users` (associação morta) | `service.professionals` |
| 2026-06-06 | `pricing.rb` | `gemini-3.5-flash` desconhecido (custo default inflado) | entrada $1,50/$9,00 por 1M |
| 2026-06-07 | `base_tool.rb` + `list_appointments_tool.rb` | evento criado pela tela da Agenda fica com `contact_id` NULO (vínculo do paciente só em `custom_attributes.patient_id`) → busca por `contact_id` voltava vazio e a Bia não citava a consulta | helpers `contact_patient_ids` + `upcoming_appointment_events` cruzam `contact_id` OU `patient_id` do contato |
| 2026-06-07 | `find_patient_by_phone_tool.rb` | WhatsApp recria o `Contact` → flag `already_linked_to_other_contact` fazia o LLM "transferir pra outro contato" | mesmo número = mesma pessoa: reconhece por telefone + `relink_to_contact!`; flag REMOVIDA; devolve `upcoming_appointments` |
| 2026-06-07 | `reschedule_appointment_tool.rb` / `cancel_appointment_tool.rb` | posse checada só por `event.contact_id` (nulo) → transferia em vez de remarcar/cancelar | `owns_appointment?` (contact_id OU patient_id do contato) + backfill do `contact_id` |
| 2026-06-07 | `period_distributor.rb` | `requested_time` ("tem às 17h?") ignorado no período "qualquer"; oferta escondia o último horário do dia | honra `requested_time` em qualquer período + leque do dia inteiro (cedo→meio→último) |
| 2026-06-07 | `guardrail/validator.rb` | travessão "—" nas mensagens ao paciente (dono não quer) | `strip_dashes` troca por vírgula na saída (preserva quebras de linha) |
| 2026-06-09 | tools de agenda (`base_tool`/`find_patient`/`list`/`cancel`/`reschedule`/`search`/`book`) | `AgendaEvent.where(...)` sem `.kept` → evento EXCLUÍDO (soft-delete `deleted_at`) ainda aparecia, era mencionado e bloqueava horário | usar o scope `kept` (`deleted_at IS NULL`) em TODA query de `AgendaEvent`; `find_patient` informa a contagem exata de consultas |

> **Cross-boundary (write):** `cancel_appointment_tool.rb` agora grava o motivo do cancelamento em `Patient#notes` (plugin `patients`, aba Cadastro) via `update_columns` — mesma fronteira já usada por `update_patient_record`. Reagendamento grava o motivo na própria consulta (`AgendaEvent#description`). Decisão do dono (2026-06-07): cancelar/reagendar **sempre** pergunta o motivo; multa só é mencionada se vier do RAG (`search_knowledge`), nunca inventada.

> **Edit CORE (autorizada pelo dono — 2026-06-09):** `app/views/api/v1/models/_contact.json.jbuilder` ganhou guard de `resource` nil. Excluir um contato no Chatwoot apaga as conversas de forma assíncrona (`dependent: :destroy_async`); entre o delete e o job (ou com o Sidekiq fora do ar) a conversa fica órfã e o partial recebia `nil` → 500 que derrubava a LISTA inteira de Conversas. Agora renderiza placeholder "Contato removido". Fora do escopo da Bea, mas o gatilho é o churn de contato do WhatsApp/bridge.

---

## 2. Mapa da arquitetura atual (onde cada coisa vive)

```
plugins/ai_agent/
├── app/
│   ├── models/ai_agent/          # GlobalSetting, AccountSetting, ConversationState,
│   │                             #   ToolDefinition, Trace, PatientMemory, FollowUpRule…
│   ├── services/ai_agent/
│   │   ├── chat_service.rb        # orquestrador do turno (LLM + guards determinísticos)
│   │   ├── chat_service/          # StateMachineUpdater, CircuitBreaker, HistoryFormatter
│   │   ├── prompt_builder.rb      # monta o system prompt (persona + clínica + estado)
│   │   ├── context_builder.rb     # prefixo por-turno (data, clínica aberta/fechada)
│   │   ├── config_resolver.rb     # hierarquia global→conta→user
│   │   ├── tool_registry.rb       # resolve key → classe da tool
│   │   ├── tools/                 # 17 tools (ver §7)
│   │   ├── humanization/          # Sentinel, Critique, EscalationRules, Sentiment
│   │   ├── emergency/, detectors/ # short-circuits determinísticos (SAMU/CVV, etc.)
│   │   ├── memory/, multimodal/   # histórico cross-conversa, áudio/imagem
│   │   └── state_machine/         # ConversationContext (pending_offer, active_service…)
│   ├── jobs/ai_agent/            # ChatResponseJob (1 turno), follow-ups, ingestão RAG
│   └── controllers/ai_agent/     # APIs de documentos, follow-up rules…
├── db/migrate/                   # migrations do plugin (inclui seeds de tools)
└── lib/ai_agent/                 # engine.rb, patches (gemini_thought_signature_patch)
```

**Fluxo de um turno** (resumo): `ChatResponseJob#perform` → `ChatService#respond` →
detectores determinísticos (emergência/ofensa/opt-out) → state-machine (confirmação curta = booking direto) →
`ContextBuilder` (prefixo) → `PromptBuilder` (system) → LLM com tools → `Guardrail::Validator` → `Sentinel` → `Trace`.

---

## 3. Registro de Mudanças Cross-Boundary (living log)

> Toda criação/edição de arquivo **fora** de `plugins/ai_agent/`. Inclui core, outros plugins, i18n, componentes.

| Data | Tipo | Arquivo(s) fora de `ai_agent` | Plugin/Core | Motivo | Status |
|------|------|-------------------------------|-------------|--------|--------|
| 2026-06-06 | Criação de rota | `lib/whatsapp/server.js` → `POST /sessions/:inboxId/presence` | Core (bridge WhatsApp/Baileys) | A presença "digitando" **não tinha rota** no bridge — o Rails postava num endpoint inexistente (404) e falhava em silêncio, por isso "sumia". Rota nova chama `sock.sendPresenceUpdate(state, to)`. Best-effort (200 mesmo desconectado). Necessário pra Fase A do typing — não dá pra mandar presença de WhatsApp de outro lugar. | ✅ feito |
| 2026-06-06 | Adição de rota | `config/routes.rb` → `resources :agenda_agent_services, only: [:index, :update]` | Core (rota) | Endpoint pra vincular serviços a um profissional (popula `agenda_service_users`). Controller fica no plugin agenda. Adição de rota = exceção automática da regra de core. | ✅ feito |
| 2026-06-06 | Edição | `app/javascript/dashboard/routes/dashboard/settings/agents/EditAgent.vue` | Core (modal de agente) | Monta `<AgentServicesField>` (componente do plugin agenda, via alias `@plugins`) no modal "Editar Agente" — campo "Serviços que atende". Pedido explícito do Leandro; sem isso não havia como vincular profissional↔serviço (e a Bia não enxergava serviços odonto). | ✅ feito |
| 2026-06-06 | Edição (factory de teste) | `spec/factories/agenda_services.rb` | Core (spec/factories) | O factory `:agenda_service` setava `price { 100.0 }`, mas a coluna `price` foi movida pra `Financial::ServicePricing` em 2026-05-22 → `NoMethodError 'price='` em qualquer spec que usasse o factory (estava órfão: nenhum spec o exercitava, por isso ninguém notou). Removida a linha morta pra a suite BIA poder usar o factory canônico. | ✅ feito |
| 2026-06-10 | Edição (i18n) | `app/javascript/dashboard/i18n/locale/pt_BR/aiAgent.json` → `AI_AGENT.FOLLOW_UPS.STEPS.*` + `CARD.CADENCE_BADGE` | Core (i18n) | Strings da UI de cadência multi-passo do follow-up (Fase 1). i18n da Klivy vive no namespace core `AI_AGENT` (pt_BR é a língua-fonte do produto; não há `en/aiAgent.json`). Adição aditiva — segue o padrão já estabelecido das demais chaves de `FOLLOW_UPS`. | ✅ feito |
| 2026-06-10 | Edição (i18n) | `app/javascript/dashboard/i18n/locale/pt_BR/aiAgent.json` → `FOLLOW_UPS.FORM.ACTION_*`/`FORM.STATIC_*`/`STEPS.STATIC_*`/`CARD.MODE_*` | Core (i18n) | Strings do modo estático (mensagem fixa com variáveis) vs Bea do follow-up (Fase 2). Mesma justificativa da entrada anterior — adição aditiva no namespace `AI_AGENT`. | ✅ feito |
| 2026-06-10 | Edição (i18n) | `app/javascript/dashboard/i18n/locale/pt_BR/aiAgent.json` → `FOLLOW_UPS.STOP.*` + `CARD.AUTO_STOP` | Core (i18n) | Strings das condições de saída (parar a sequência ao responder/agendar) do follow-up (Fase 3). Adição aditiva no namespace `AI_AGENT`. | ✅ feito |
| 2026-06-10 | Edição (i18n) | `app/javascript/dashboard/i18n/locale/pt_BR/aiAgent.json` → `FOLLOW_UPS.TEMPLATE.*` + `CARD.HAS_TEMPLATE` | Core (i18n) | Strings do fallback de template fora da janela de 24h (Fase 4). Adição aditiva no namespace `AI_AGENT`. | ✅ feito |
| 2026-06-10 | Dependência (leitura) | `Conversation#can_reply?` / `Whatsapp::SendOnWhatsappService` / `Channel::Whatsapp#message_templates` | Core (Chatwoot) | `OutboundMessage` (Fase 4) lê `conversation.can_reply?` p/ decidir texto×template e popula `additional_attributes['template_params']` pro envio HSM nativo. Só leitura/uso da convenção — nenhum arquivo core editado. | ✅ feito |
| 2026-06-10 | Edição (i18n) | `app/javascript/dashboard/i18n/locale/pt_BR/aiAgent.json` → `FOLLOW_UPS.FORM.PERSONA_*` | Core (i18n) | Strings do tom/persona por tipo do follow-up (Fase 5). Adição aditiva no namespace `AI_AGENT`. | ✅ feito |
| 2026-06-10 | Dependência (leitura) | `Conversation#messages` (incoming/outgoing não-privadas) | Core (Chatwoot) | `MessageGenerator` (Fase 5) lê as últimas 8 mensagens da conversa-alvo pra dar continuidade no follow-up generativo. Só leitura. | ✅ feito |
| 2026-06-11 | Edição (i18n) | `app/javascript/dashboard/i18n/locale/pt_BR/aiAgent.json` → `FOLLOW_UPS.TRIGGERS.SERVICE_RECALL_*`/`SERVICE.*`/`CARD.RECALL_EVERY` | Core (i18n) | Strings da reativação por serviço (Fase 6). Adição aditiva no namespace `AI_AGENT`. | ✅ feito |
| 2026-06-11 | Dependência (leitura, frontend) | `@plugins/agenda/frontend/api/agendaServices` | Plugin agenda (FE) | A tela de follow-ups busca a lista de serviços (read-only) pro picker de reativação, via o API client do próprio agenda. Sem store/escrita. | ✅ feito |
| 2026-06-11 | Injeção de comportamento (DI) | `plugins/ai_agent/lib/ai_agent/engine.rb` → `AgendaEvent.after_commit :dispatch_appointment_confirmed_follow_ups` | Plugin agenda (model, via to_prepare class_eval) | Auditoria: o trigger `appointment_confirmed` nunca disparava (job nunca enfileirado). Ligado via DI no engine do ai_agent (mesmo `class_eval` que já estende AgendaEvent) — NÃO editamos o arquivo do plugin agenda. Dispara `DispatchAppointmentConfirmedJob` na criação confirmada / transição de status. | ✅ feito |
| 2026-06-11 | Dependência (leitura) | `SessionLog`/`TreatmentItem` (patients), `AgendaService`/`AgendaEvent` (agenda), `Patient#contact_id` (patients) | Outros plugins | `ServiceRecallFinder` (Fase 6) lê a última sessão assinada de um serviço (`SessionLog.signed`→`treatment_item.agenda_service_id`), resolve o `contact_id` via `Patient`, e checa reagendamento futuro do serviço (`AgendaEvent`). Tudo defensivo (`defined?`) e escopado por `account_id`; nenhum write/edição nesses plugins. Intervalo de recorrência fica no card (ai_agent), não no AgendaService, justamente pra evitar editar o agenda + o serializer core. | ✅ feito |

---

## 4. Mapa de Dependências Externas (leituras)

> O que a Bea **usa** de fora sem (idealmente) modificar. Se uma dessas mudar de schema, a Bea pode quebrar — por isso o acesso é defensivo (§1.4).

| Recurso externo | Dono | Como a Bea usa | Onde (em `ai_agent`) |
|-----------------|------|----------------|----------------------|
| `AgendaService` | plugin `agenda` | catálogo de serviços (nome, `duration_minutes`) | `prompt_builder.rb`, `clinic_info_tool`, `search_available_slots_tool` |
| `AgendaEvent` / `AgendaSetting` | plugin `agenda` | criar/checar agendamentos, horário de funcionamento | `book_*`/`cancel_*`/`reschedule_*`/`search_available_slots` tools |
| **`WaitingListEntry`** | plugin `agenda` | **lista de espera** — upsert por `contact_id` (`period` enum `morning\|afternoon\|evening`, `preferred_days[]`, `specific_time`, `notes`) | `add_to_waiting_list_tool.rb` ✅ |
| `Patient` | plugin `patients` | ficha do paciente. Colunas relevantes: `cpf`, `birthdate`, `has_guardian`, `guardian`, `origin`, `responsible_professional_id` | `patient_lookup`, `create_patient_minimal`, `*_appointment` tools |
| `Patient` (ESCRITA) | plugin `patients` | grava `cpf` / `origin` / `guardian` (+`has_guardian` via update_columns) | `update_patient_record_tool.rb` ✅ |
| `Captain::Assistant` (linha "Beatriz") | core/captain | dados da clínica (nome, endereço, horários, mensagens) injetados no prompt | `prompt_builder.rb#beatriz_assistant_block` |
| `InstallationConfig` (`CAPTAIN_*`) | core | provider, API keys, modelo, system prompt da Bea | `chat_service.rb`, `prompt_builder.rb` |
| `Contact` / `Conversation` / `Message` | core | identidade, histórico, envio de resposta | `chat_service.rb`, `chat_response_job.rb` |

---

## 5. Registro de Componentes

> Componentes Vue **criados** ou **reutilizados** no trabalho da Bea. Reuso > criação.

| Componente | Local | Criado/Reutilizado | Usado por / Observação |
|-----------|-------|--------------------|------------------------|
| `WaitingListModal.vue` | `app/javascript/.../conversation/contact/` (core) | **Existente** | Modal da lista de espera (manual). A Bea automatiza via model, sem tocar neste componente. |
| `WaitingListSidebarSection.vue`, `WaitingListSlotBadge.vue` | `plugins/agenda/frontend/features/waiting-list/` | **Existente** | Feature de waitlist no agenda. |
| **`AgentServicesField.vue`** | `plugins/agenda/frontend/features/settings/components/` | **Criado (2026-06-06)** | Chips de serviços no modal "Editar Agente". Vincula profissional↔serviço (`agenda_service_users`) com auto-save. Montado no core `EditAgent.vue` via `@plugins`. API: `agendaAgentServices.js`. |

_(Novos componentes da Bea entram aqui ao serem criados.)_

---

## 6. Decisões de Produto (Bea)

| Data | Decisão | Detalhe / Impacto |
|------|---------|-------------------|
| 2026-06-06 | **Provider primário = Gemini `gemini-3.5-flash`** | ✅ CONFIRMADO funcionando end-to-end (provider=gemini, tool-calling OK). Modelo é real (doc oficial Google); o registro do `ruby_llm` é que estava velho. Fallback OpenAI `gpt-4.1-mini` ativo. Config em `InstallationConfig` (`CAPTAIN_LLM_PROVIDER=gemini`, `CAPTAIN_GEMINI_MODEL=gemini-3.5-flash`). Preço adicionado ao `AiAgent::Pricing` ($1,50/$9,00 por 1M). |
| 2026-06-06 | **Áudio = OpenAI Whisper (independente do chat)** | Transcrição usa `whisper-1` (endpoint dedicado `api.openai.com/v1/audio/transcriptions`, key OpenAI própria). Trocar o chat pra Gemini NÃO afeta o áudio. Mantém `CAPTAIN_OPEN_AI_API_KEY`. |
| 2026-06-06 | **Gemini thinking desligado** (`thinkingBudget: 0`) | `gemini-3.5-flash` é modelo de *thinking* (gastava 1000+ tokens de raciocínio → turno de 40-80s). `ChatService#apply_provider_tuning` injeta `thinkingConfig.thinkingBudget=0` via `with_params`. Valores > 0 quebram o parser do ruby_llm 1.9.2. |
| 2026-06-06 | ⚠️ **Key do Gemini = TIER GRATUITO (quota limitada)** | A latência alta (~25s/chamada) e os erros eram **rate-limit do free tier**, esgotado nos testes. Leandro migrou pra **PAID tier** (2026-06-06) → `gemini-3.5-flash` agora responde em ~2-6s. `RateLimitError` continua com fallback automático pro OpenAI `gpt-4.1-mini`. |
| 2026-06-06 | 🔒 **Modelo forçado via `GlobalSetting` (anti-reset)** | `CAPTAIN_LLM_PROVIDER`/`CAPTAIN_GEMINI_MODEL` (InstallationConfig) foram vistos **resetando** para openai/"" (re-seed no boot) → ChatService voltava pro OpenAI silenciosamente. Fix robusto: `AiAgent::GlobalSetting.current.chat_model = "gemini-3.5-flash"`. O `ConfigResolver#chat_model` usa isso como OVERRIDE que vence o InstallationConfig e **não reseta** (tabela do plugin `ai_agent_global_settings`). `provider_for_model` infere `:gemini` pelo nome. |
| 2026-06-06 | **CPF obrigatório no cadastro (Nome + CPF)** | Auditoria BIA.md (passo 2.6): o mínimo da ficha é **nome completo + CPF**. `create_patient_minimal` passou a exigir CPF (param `cpf`, normaliza p/ 11 dígitos, retorna `missing_cpf` se faltar) e o prompt pede os dois ANTES de agendar. Exceção: dependente **menor** entra só com nome + `birthdate` (CPF opcional — responsável regulariza). **Supersede** as decisões anteriores do mesmo fluxo ("nunca pedir", 2026-05-07; "pedir só ao agendar"). Decisão explícita do Leandro. |
| 2026-06-06 | **Prompt da Bia versionado + suite de testes BIA.md** | O `CAPTAIN_BEA_SYSTEM_PROMPT` (antes só no banco via `/super_admin/bea`) ganhou cópia canônica versionada em `plugins/ai_agent/config/bea_system_prompt.txt` (backup + contrato de CI). Suite de regressão dos fluxos em `plugins/ai_agent/spec/flows/bia/` (59 exemplos: regras das tools, roteamento determinístico, cobertura de prompt — cada exemplo rastreável a um caso T01–T23). O InstallationConfig segue como fonte de runtime (editável na UI); o arquivo do repo é a referência revisável e o que o spec de cobertura valida. |
| 2026-06-06 | **Preço: pendente** | `agenda_services` não tem campo de preço. Por ora a Bea **não cota preço**. Campo a adicionar depois (lembrar o Leandro). |
| 2026-06-06 | **Lista de espera: reutiliza `agenda::WaitingListEntry`** | Não cria tabela nova. Tool da Bea instancia o model existente. |
| 2026-06-06 | **Persona = "Bia" + age como humana** | Nome patient-facing = **Bia** (NÃO "Bea" — Bea/Beatriz é só interno: `AgentBotIdentity.name`, `Captain::Assistant`). No `CAPTAIN_BEA_SYSTEM_PROMPT`: não se anuncia como assistente virtual; só admite se perguntarem direto (e sem vazar a regra); encaminhamentos com fala humana ("vou confirmar com a equipe e te retorno"), nunca "transferir para atendente humano". ⚠️ CFM 2.454/2026 (referenciada no código) pede menção identificável de IA — mitigado por "honesta quando perguntam" + bloco do responsável técnico. Decisão de produto do Leandro. |
| 2026-06-06 | **"Lista" de serviços = catálogo com profissional vinculado** | `clinic_info` só mostra `AgendaService` que tenha ≥1 profissional (`AgendaServiceUser`). A clínica tem serviços odonto (Ortodontia, Implanto, etc.) mas SEM dentista vinculado → invisíveis pra Bia → ela escala. **Não é bug**: pra Bia oferecer odonto, vincular um profissional aos serviços no Agenda. |

---

## 7. Inventário de Tools (referência)

17 tools registradas (`AiAgent::ToolDefinition`). Mapa com o fluxo receptivo da BIA:

| Tool | Passo do fluxo |
|------|----------------|
| `find_patient_by_phone` | busca por telefone |
| `confirm_patient_identity` | confirma paciente cadastrado [1.1] |
| `patient_lookup` | resolve prontuário |
| `create_patient_minimal` | cadastro [2.6] (nome; CPF no booking) |
| `list_appointments` | tem consulta agendada? |
| `clinic_info` | endereço, horários, serviços |
| `search_available_slots` | busca de horários (resolve profissional por serviço) |
| `book_appointment` | agenda [2.2] |
| `cancel_appointment` | cancelamento [1.6] |
| `reschedule_appointment` | reagendamento [1.7] |
| `search_knowledge` | dúvidas / multas via RAG |
| `transfer_to_human` | passar p/ recepção [1.8] |
| `financial_status` | situação financeira |
| `notify_staff` | nota interna p/ recepção |
| `erasure_request` | LGPD |
| `add_to_waiting_list` ✅ | lista de espera [2.3/2.4/2.5] |
| `update_patient_record` ✅ | CPF (ao agendar), origem ("como conheceu") e responsável do menor |

---

## 8. Backlog do fluxo BIA (alto nível)

> Status: **Fases 1-4 entregues** (2026-06-06). Pendentes: RAG de políticas e campo de preço.

- [x] **Prompt do fluxo** — `CAPTAIN_BEA_SYSTEM_PROMPT` reescrito (1541→7642 chars), árvore em estágios + regras de tool. Síntese do painel de jurados (D2 venceu).
- [x] **Tool `add_to_waiting_list`** — cria `agenda::WaitingListEntry` (upsert por contact_id; mapeia manhã/tarde/noite → morning/afternoon/evening).
- [x] **CPF no booking** — `update_patient_record(cpf:)` valida 11 dígitos e grava em `Patient.cpf` (pedido só ao confirmar).
- [x] **Dependente/menor [1.5]** — `update_patient_record(guardian_name:, guardian_birthdate:)` grava `guardian` (jsonb) + `has_guardian` via update_columns (evita validação de guardian_cpf).
- [x] **"Como conheceu" → `Patient.origin`** — `update_patient_record(origin:)`.
- [ ] **RAG de políticas (multa)** — popular base de conhecimento.
- [x] **Anti-alucinação Gemini** — `thinkingBudget: 0` + tool-grounding no prompt + fallback OpenAI. (Sentinel-regenerar ainda em telemetria.)
- [ ] **Preço** — (bloqueado) decisão de campo pendente.
