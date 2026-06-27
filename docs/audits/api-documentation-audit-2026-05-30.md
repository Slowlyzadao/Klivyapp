# Auditoria Profunda de Documentação de APIs — `financial` · `ai_agent` · `internal_chat`

> **Data:** 2026-05-30
> **Escopo:** `plugins/financial`, `plugins/ai_agent`, `plugins/internal_chat` — APIs REST, payloads, RBAC, fluxos e cobertura de documentação (OpenAPI/Scalar + docs de produto).
> **Princípio:** o **código-fonte é a única fonte de verdade**. Toda afirmação foi verificada contra `config/routes.rb`, os controllers reais, models, policies, services e jobs. Nada foi assumido.
> **Metodologia:** 16 agentes em pipeline (10 extratores de ground-truth → 3 analisadores de divergência → 3 construtores de matriz com reconciliação adversarial). 1.8M tokens, 633 chamadas de ferramenta. Cada achado cita `arquivo:linha`.
> **Artefato companheiro:** [Matriz Completa de APIs](api-matrix-2026-05-30.md) (204 endpoints, linha a linha).

---

## 1. Resumo executivo

| Métrica | Valor |
|---|---|
| **Endpoints reais mapeados** (3 módulos) | **204** (financial 149 · ai_agent 18 API + 3 super_admin · internal_chat 37) |
| **Endpoints com documentação** (swagger) | **152** |
| **Endpoints SEM documentação** | **52** (financial 43 · internal_chat 9) + 3 rotas HTML super_admin (fora do swagger por design) |
| **Cobertura de existência** | **75%** (financial 71% · ai_agent 100% · internal_chat 76%) |
| **Achados de divergência catalogados** | **65** (financial 19 · ai_agent 19 · internal_chat 27) |
| **Divergências confirmadas / rejeitadas** (verificação adversarial) | **65 / 0** |
| **Docs órfãos** (swagger apontando p/ rota inexistente) | **1** (`_index.yml.bak`, backup morto v1) |

### A história em uma frase por módulo

- **Financial** — cobertura de *existência* 71%, mas há **6 controllers inteiros sem nenhum swagger** (RecurringBillings, PaymentMethods, PaymentMethodFees, ServicePricings, AgentProfiles, PeriodClosures = 28 endpoints) + 7 relatórios + simulate_plan + restore_defaults + revenue_goal(show/update). A doc de produto/RBAC (`configuracoes.md`) descreve um modelo de permissões **fantasma** (`financial.*`) que já derrubou a aba financeira do paciente 2×.
- **AI Agent (Bea)** — cobertura de *existência* 100% (18/18 endpoints têm swagger), mas **14 dos 18 estão imprecisos**: contratos quebrados (`rating` string vs integer no feedback, `account_id` obrigatório omitido), schemas que descrevem campos que o serializer nunca emite, e enums com valores inválidos. Além disso, **toda a riqueza arquitetural** (21 tools LLM, providers, guardrails, RAG, crons fan-out, config 3-camadas) **não tem documentação** além de 1 diagrama no README.
- **Internal Chat** — cobertura de *existência* 76% (memberships, typing, attachments sem doc), mas o problema central é **deriva sistêmica de contrato**: quase todo endpoint documentado erra o **status code** (`204`/`201` documentados, código retorna `200`) e o **envelope de resposta** (código retorna `{data: …}`, doc aponta o schema direto). Definitions `Message.yml`/`Room.yml` omitem a maioria dos campos reais dos serializers.

### Risco principal

> A maior ameaça **não** é a cobertura de existência (75% é razoável), e sim a **imprecisão** dos endpoints já documentados. Um cliente que segue a doc **quebra em produção** em casos concretos: `POST /ai_agent/feedback` com `rating: "thumbs_up"` retorna 422 (código espera `1|-1`); `POST /internal_chat/rooms` com `include_ai_agent: true` **não adiciona a Bea** (código lê `add_bea`); a doc do webhook Asaas vaza códigos `401/404` que o código foi endurecido (CRIT-SEC-02) para esconder atrás de um `403` constante.

---

## 2. Cobertura encontrada (matriz de documentação)

| Módulo | Possui API Docs? | Completo? | Atualizado/Preciso? | Observações |
|---|---|---|---|---|
| **financial** | Sim — swagger (80 paths, 25 definitions) wirado em `swagger/plugins_index.yml` | **Não** (71% — 43 rotas sem path) | **Parcial** | 6 controllers sem swagger; sem README no plugin; `_index.yml.bak` órfão; canon `financeiro-funcionamento.md` não cita os módulos novos; `configuracoes.md` com RBAC fantasma |
| **ai_agent** | Sim — swagger (9 paths, 3 definitions) + README com diagrama | **Parcial** (100% endpoints, 0% arquitetura) | **Não** (14/18 imprecisos) | Tools/providers/guardrail/RAG/crons/config sem doc; contratos do feedback e health desatualizados (pré-SEC-27/SEC-28); enums inválidos |
| **internal_chat** | Sim — swagger (9 paths, 2 definitions) + README + PRD | **Não** (76% — memberships/typing/attachments sem doc) | **Não** (deriva sistêmica de status/envelope) | Camada realtime (ActionCable) não documentada; definitions omitem campos dos serializers |

### Inventário de documentos analisados

**Swagger (OpenAPI):** `plugins/{financial,ai_agent,internal_chat}/swagger/{paths,definitions,common.yml}` agregados em `swagger/plugins_index.yml` (raiz) → build via `lib/tasks/swagger.rake`.
**Produto:** `docs/01-product/modules/{financeiro,financeiro-funcionamento,configuracoes,chat-interno,PRD-chat-interno}.md`.
**Engenharia/Auditoria:** `docs/03-engineering/financeiro-*`, `docs/audits/{financial-2026-05,financial-2026-05-implementation,ai-agent-internal-chat-audit}.md`.
**READMEs de plugin:** `ai_agent/README.md`, `internal_chat/README.md` (financial **não tem**).

---

## 3. Auditoria de rotas

Mapa completo (método, endpoint, controller#action, auth, RBAC, doc, precisão) em **[api-matrix-2026-05-30.md](api-matrix-2026-05-30.md)**. Resumo:

| Módulo | GET | POST | PATCH/PUT | DELETE | Total | Webhooks | Públicas | Super Admin |
|---|---|---|---|---|---|---|---|---|
| financial | ~60 | ~45 | ~24 | ~20 | 149 | 1 (Asaas) | 1 (webhook) | 0 |
| ai_agent | ~7 | ~7 | ~4 | ~3 | 18 (+3) | 0 | 2 (`health`, `feedback`) | 3 (HTML docs) |
| internal_chat | ~13 | ~13 | ~7 | ~4 | 37 | 0 | 0 | 0 |

Todas as rotas vivem em um único `config/routes.rb` (1286 linhas): financial em **406–645** + webhook **1153**; ai_agent em **56–57** (público) + **146–170** (CRUD) + **1211** (super_admin); internal_chat em **177–224**.

---

## 4. Auditoria de permissões (RBAC)

O RBAC real **diverge** do que parte da documentação afirma. Modelo real por módulo:

- **financial** — não usa Pundit. Gating por `require_role!`/`authorize_write!`/`authorize_admin!` no `base_controller`, mapeando para presets `ADMIN`/`GERENTE`/`RECEPCAO`/`AUDITOR`/`DENTIST`. A **aba financeira do paciente** (`patient_summaries#show`, `patient_timelines#show`) é gateada por `patients.view_financial` (Klivy RBAC), **não** por `financial.*`. Achados:
  - `payment_methods#rename_provider` **não tem gate de role** (todas as outras escritas do controller exigem ADMIN/GERENTE) — possível bug de segurança a avaliar.
  - `installments#pay`/`#refund` e `entries#create/update/destroy` (baixa, estorno, lançamento) **sem gate de role** — qualquer usuário autenticado da conta executa. A doc não alerta.
  - `revenue_goals` é GERENTE/ADMIN em **todas** as actions (inclui index/show), mas o swagger não documenta 403.
  - Resíduo: `require_role!` ainda mapeia `'dono'` dentro do preset ADMIN (`base_controller.rb:75`) apesar de `dono` ter sido removido do RBAC em 2026-04-30 — verificar.
- **ai_agent** — Pundit no módulo `captain` (`view`/`manage_documents`/`manage_follow_ups`/`manage_templates`). Tools internas (Pipeline B) checam permissão do `invoking_user` (`agenda:create_event/edit_event/cancel_event/view`, `patients:view`). Rotas super_admin: gate por sessão Devise super_admin (sem Pundit) — `destroy` faz `find` **sem scope de account** (super_admin pode apagar doc de qualquer conta).
- **internal_chat** — Pundit por **room role** (`owner`/`admin` da sala), com bypass de admin de conta na maioria das policies. **Exceções importantes**: `TypingPolicy` **não** tem bypass de admin não-membro (intencional); a permissão de catálogo `internal_chat.manage_memberships` existe mas **não é enforced** (gate real é por room role). A doc de `messages#update` diz "admin OR author", mas **edit é só do autor** (admin não bypassa autoria); só `delete` é "admin OR author".

**Divergência crítica de doc RBAC:** `docs/01-product/modules/configuracoes.md` documenta chaves `financial.view_transactions`, `create_estimate`, `approve_estimate`, etc. — **chaves fantasma** que não existem no RBAC atual (Pundit `TransactionPolicy`/`FinancialEstimatePolicy` foi substituído por KlivyRole desde 2026-04-30). Essas chaves já fizeram a aba financeira sumir 2×.

---

## 5. Auditoria de fluxos (reconstruídos do código)

### 5.1 Financial — Plano → Orçamento → Parcelas → Pagamento → Caixa → DRE
```
TreatmentPlan#approve ─→ Budget(rascunho/enviado, origin=orcamento|plano_tratamento) + BudgetItems
   └→ ApproveBudget: status→aprovado · gera N Installments (split centavos, resto na última)
        · provisiona CommissionEntry · sync gateway (cria charges Asaas) · auto-recebe pernas on_confirm
   └→ ReceivePayment: PaymentReceipt(+Items) · congela snapshot fee/MDR no Installment (anti-tamper)
        · cria Entry(receita, in) · move PatientCredit · vira CommissionEntry provisionada→devida
   └→ CashRegister/CashMovement (caixa) · Entry alimenta Dashboard + DreReport
   └→ PayCommission: devida→paga (gera Expense) · RefundPayment: estorna proporcional (Entry/PatientCredit/Refund)
```
- **Mensalidade fixa** = `Financial::RecurringBilling` (motor real, job 02:30 UTC gera Budget+Installment por período), **separado** do `Budget(origin=mensalidade)` legacy. **Não documentado em lugar nenhum.**
- **Baixa automática cartão**: `PaymentMethod.settlement_mode=on_due_date` → `AutoSettleCardInstallmentsJob` (03:30). `manual`/`on_confirm`/`on_due_date`; boleto/convênio/parcelamento_próprio **nunca** on_due_date.
- **Fechamento contábil**: `PeriodClosure` (append-only, ADMIN) bloqueia edição retroativa (`Errors::PeriodClosed` → 423 Locked). **Não documentado.**

### 5.2 AI Agent (Bea) — Pipeline A (paciente) e Pipeline B (staff)
```
A) Paciente WhatsApp → Message.after_create_commit (callback direto, NÃO Wisper) → MessageListener
     → ChatResponseJob (coalescing + idempotency por Trace) → ChatService:
        guards → emergency(SAMU/CVV) → captain quota → escalation → state machine
        → LLM (Gemini/OpenAI + tools) → guardrail → sentinel(opt-in) → Trace(custo/latência)
     → Tools: search_available_slots, book/reschedule/cancel, create_patient_minimal,
              financial_status, transfer_to_human, search_knowledge(RAG), notify_staff, …
B) Staff menciona @beatriz no Chat Interno → AiAgentMentionListener → RespondJob
     → InternalChat::Responder (6 tools privilegiadas, checa RBAC do invoking_user)
```
- Crons registrados **em runtime** no `engine.rb` (não em `schedule.yml`): ProactiveOutreach `0 17 * * *`, ConsolidatePatientMemory `0 7 * * *`, FollowUpDispatcher `* * * * *`, Health::Monitor `*/10`. **Gap de descoberta.**

### 5.3 Internal Chat — Mensagem → Persistência → Broadcast → Notificação
```
POST /messages → MessageDispatcher (cria Message, content_type DERIVADO server-side,
   content_attributes allowlist SEC-21, converte imagem→WebP, cap 15 anexos)
   → BroadcastMessageJob (fan-out ActionCable via UserBroadcaster → user.pubsub_token)
   → MentionExtractor (@user → mentioned_user_ids; @beatriz → Pipeline B da Bea)
Eventos realtime: internal_chat.message.created/.updated/.mention.created/.typing/
   .read_receipt.updated/.room.updated/.room.deleted — SEM documentação (OpenAPI não cobre WS).
```

---

## 6. Divergências (catalogadas, 65 — todas confirmadas)

> Detalhe completo com evidência `arquivo:linha` nos anexos por módulo (§9). Aqui, o destaque por severidade.

### 6.1 Financial (19)

**Críticas (3)**
1. `webhook_asaas.yml` documenta `401/403/404` distintos — o controller retorna **`403` constante** em toda pré-condição (anti-enumeração CRIT-SEC-02). **A doc vaza o que o código foi endurecido para esconder.** → remover 401/404, manter 403 "constante por design".
2. **RecurringBillings** (8 endpoints, motor de mensalidade fixa) — **zero swagger**, ausente do `plugins_index.yml` e do canon.
3. **PaymentMethods + PaymentMethodFees** (~12 endpoints, infraestrutura de baixa) — **zero swagger**. `rename_provider` sem RBAC.

**Altas (8):** ServicePricings, AgentProfiles (dados bancários, ADMIN-only), PeriodClosures sem swagger; `budgets/:id/simulate_plan` sem doc; `revenue_goal.yml` documenta só `delete` (omite show/update) e diz `204` quando o código **encerra** (active=false) e responde `200` com objeto; RBAC GERENTE/ADMIN de revenue_goals sem 403 na doc; `revenue_goals.yml` documenta query `year` (campo morto — modelo usa `start_date/end_date`).

**Médias (6):** 7 relatórios sem doc (top_procedures, revenue_vs_goal, revenue_by_procedure/payment_method/professional_table, account_statement, goals_vs_actual); `installment_pay.yml` omite `payment_method_id` e modifiers `type/value`; pay/refund/entries sem RBAC não sinalizado; `412` (setup incompleto) ausente em quase todos os paths; create de budget sem RBAC não sinalizado; canon `financeiro-funcionamento.md` sem os 5 módulos novos.

**Baixas (2):** `_index.yml.bak` órfão (path v1 morto) → remover; `entries.yml` omite filtro `payment_method`.

### 6.2 AI Agent (19)

**Críticas (2)** — contratos quebrados em `POST /ai_agent/feedback`:
1. `rating` doc=string `[thumbs_up,thumbs_down]`; código = **integer `1|-1`** (`to_i`). Cliente seguindo a doc **quebra 100%**.
2. `account_id` **obrigatório** no código (assina HMAC SEC-11) mas **ausente** da doc.

**Altas (6):** `429` (rate limit SEC-28) não documentado; `GET /health` expõe `metrics`/`alerts` na doc que o código **filtra** para `{status, checked_at}` (SEC-27); `POST /documents` request body errado (`source_type`/`content` não aceitos; tipo é auto-inferido; `text` impossível via API); `Document.yml` descreve campos que o serializer nunca emite e omite os reais; `reset` faz o **oposto** do documentado (força room/reception/enabled=true, sobrescreve name+body); crons da Bea fora do `schedule.yml`.

**Médias (7):** `Document.status` é string-enum (`processed`, não `ready`/integer); `FollowUpRule.offset_unit` enum inclui `days` **inválido** (422); `trigger_type` omite `appointment_confirmed` (válido, event-driven); `InternalNotificationTemplate` serializer retorna 5 campos extras não documentados; `catalog` omite campos; **catálogo de 21 tools sem doc**; **flags CAPTAIN_* sem doc** (Sentinel/Sentiment OFF por padrão — risco de achar que estão ativos).

**Baixas (4):** `comment` maxLength doc=1000 vs código 500; `detector_status` derivado/fallback não explicado; PATCH não documentado (só PUT); comentário stale no model (cron "15min" vs real 1min).

### 6.3 Internal Chat (27)

**Crítica (1):** Memberships (CRUD de membros, 4 endpoints) **sem nenhuma doc**.

**Altas (5):** Typing e Attachments (3 endpoints) sem doc; `POST /rooms` usa `include_ai_agent` na doc mas código lê **`add_bea`** (cliente não adiciona a Bea); `unread_summary` shape divergente (`{data:{room_id:int}, total}` vs doc `{total, by_room:{…}}`); `Message.yml` omite a maioria dos campos do serializer (attachments, reactions, sticker, mentions, in_reply_to, is_favorited).

**Médias (~13):** deriva sistêmica de **status code** (`favorite/react/sticker/mute/delete` documentados `201`/`204`, código retorna **`200`**) e de **envelope** (`{data:…}` não refletido); `archived` query inexistente; `mark_read` exige body `{message_id}` (doc diz "marca todas"); `mentions` shape achatado; `stickers` campo `favorited`→`is_favorite` + 8 campos; `Room.yml` omite `members[]`/`unread_count`; enum `content_type` omite `sticker`; `content_type` enviável na doc mas **derivado** server-side; `manage_memberships` não enforced; edit RBAC "admin OR author" errado.

**Baixas (~8):** `unreact` body ignorado; `mentions` query `unread_only`→`status`; campos `unread`→`count`, `marked_count` inexistente; sticker `maxLength` não enforced; messages `limit` default 50→30; edit 422s ausentes; sticker unfavorite campo `deleted`; **camada realtime ActionCable sem doc**.

---

## 7. Documentação órfã, código órfão e endpoints mortos

- **Doc órfã / morta:** `plugins/financial/swagger/_index.yml.bak` aponta para `/api/v1/financial/transactions` — endpoint v1 **removido** em 2026-05-22 (drop de tabelas legacy). → **remover o arquivo**.
- **Doc que descreve convenção não seguida:** `docs/api-documentation-strategy.md` afirma que cada plugin tem `swagger/index.yml` — falso para `financial` (só `_index.yml.bak` desativado; é wirado direto no índice global).
- **Doc com modelo morto:** `configuracoes.md` (RBAC `financial.*` fantasma) e `financeiro.md` (arquitetura V1 `account_transactions`, auto-declarado histórico).
- **Código órfão / sem doc:** 52 endpoints sem swagger (§6); 21 tools LLM, providers, guardrail, RAG, state machine, 15 models da Bea sem doc; camada realtime do chat sem doc.
- **Endpoints mortos (rota sem código):** **nenhum** — 0 docs órfãos no índice ativo; todo path wirado tem rota real.
- **Afirmações conflitantes entre docs:** `financial-2026-05-implementation.md` diz "sem cliente real em produção" enquanto `financeiro.md` cita a conta Mamedes #31 com 1.987 parcelas importadas.

---

## 8. Riscos e recomendações

### Riscos
| # | Risco | Severidade | Evidência |
|---|---|---|---|
| R1 | Cliente seguindo a doc **quebra em produção** (feedback rating/account_id; rooms `add_bea`; health) | 🔴 Alta | §6.2, §6.3 |
| R2 | Doc do webhook Asaas **vaza superfície de enumeração** que o código mitiga (CRIT-SEC-02) | 🔴 Alta | §6.1 |
| R3 | RBAC documentado **fantasma** (`financial.*`) pode derrubar a aba financeira de novo | 🔴 Alta | §4 |
| R4 | 6 controllers financeiros centrais (mensalidade, formas de pagamento, fechamento) **invisíveis** para integradores | 🟠 Média | §6.1 |
| R5 | ~~`rename_provider` e baixa/estorno/lançamento **sem RBAC**~~ → **CORRIGIDO** | ✅ Resolvido | §12 |
| R6 | Arquitetura da Bea (tools, guardrails, custo, crons) só no código → **bus factor** | 🟠 Média | §5.2, §9 |

### Recomendações (prioritizadas)
1. **Corrigir os contratos quebrados** (R1) — `ai_agent_public.yml`, `internal_chat_rooms.yml`. *(aplicado nesta auditoria)*
2. **Remover 401/404 do webhook** + nota "403 constante por design" (R2). *(aplicado)*
3. **Substituir o RBAC fantasma** em `configuracoes.md` pelo modelo real KlivyRole (R3). *(aplicado)*
4. **Documentar os 52 endpoints** faltantes (swagger + `plugins_index.yml`) (R4). *(aplicado p/ os 6 controllers + reports)*
5. **Padronizar status/envelope** do internal_chat (`200` + `{data:…}`) na doc (R6 da §6.3). *(aplicado)*
6. **Criar doc de arquitetura da Bea** (tools, providers, guardrail, RAG, crons, flags) e **README do financial**. *(aplicado)*
7. **Adotar geração de swagger a partir de specs** (request/RSwag) para evitar drift futuro — *recomendação de processo, fora do escopo desta auditoria.*

---

## 9. Anexos — divergências detalhadas com evidência

Os achados completos, item a item, com `documented` / `actual` / `evidence (arquivo:linha)` / `recommendation`, estão preservados em:
- Financial: 19 achados — vide §6.1 e a matriz.
- AI Agent: 19 achados — vide §6.2.
- Internal Chat: 27 achados — vide §6.3.

> Esta auditoria foi gerada com verificação adversarial (cada divergência de endpoint foi reconfirmada contra `config/routes.rb` e os arquivos swagger antes de entrar no relatório). **65/65 confirmadas, 0 rejeitadas.**

---

## 10. Números finais (entregáveis)

| # | Métrica | Valor |
|---|---|---|
| 1 | **Total de endpoints encontrados** | **204** (financial 149 · ai_agent 18 API + 3 super_admin · internal_chat 37) |
| 2 | **Endpoints documentados** | **152** |
| 3 | **Endpoints NÃO documentados** | **52** (+3 HTML super_admin, fora do swagger por design) |
| 4 | **Divergências encontradas** | **65 catalogadas** (cobrindo 52 endpoints sem doc + ~46 imprecisões de payload/status/RBAC em endpoints documentados) |
| 5 | **Documentos atualizados** | **30** (16 swagger paths corrigidos + 6 definitions + 1 comentário de model + `swagger/plugins_index.yml` + `configuracoes.md` + `financeiro-funcionamento.md` + 4 fixes restantes) — lista em §11 |
| 6 | **Documentos criados** | **48** (29 swagger paths + 9 definitions financeiras/chat + 2 narrativos + README financeiro + doc de arquitetura da Bea + doc realtime do chat + este relatório + a matriz) — lista em §11 |
| 7 | **Cobertura final de documentação** | **Existência: 75% → ~100%** (os 52 endpoints sem doc foram documentados e wirados no índice; restam fora só as 3 rotas HTML super_admin, por design). **Precisão: 65 divergências corrigidas** (webhook, RBAC fantasma, contratos quebrados, envelopes/status do chat, enums da Bea). |

---

## 11. Documentos criados e atualizados (remediação)

> Remediação aplicada na mesma data (2026-05-30) por geração/correção grounded-in-code (18 agentes escrevendo arquivos distintos + wiring manual do índice). Todos os 69 fragmentos swagger gerados/editados passam em validação YAML; o `swagger/plugins_index.yml` resolve **317/317** `$ref`s com **0** chaves de path duplicadas.

### 11.1 Criados (48)

**Deliverables de auditoria (2)**
- `docs/audits/api-documentation-audit-2026-05-30.md` (este relatório)
- `docs/audits/api-matrix-2026-05-30.md` (matriz de 204 endpoints)

**Financial — swagger novo (35):** 29 path files + 6 definitions
- Mensalidades: `recurring_billings.yml`, `recurring_billing.yml`, `recurring_billing_{pause,resume,cancel}.yml` + `definitions/RecurringBilling.yml`
- Formas de Pagamento: `payment_methods.yml`, `payment_method.yml`, `payment_method_simulate_fee.yml`, `payment_methods_{rename,destroy}_provider.yml`, `payment_method_fees.yml`, `payment_method_fee.yml`, `payment_method_fee_deactivate.yml` + `definitions/PaymentMethod.yml`, `PaymentMethodFee.yml`
- Precificação: `service_pricings.yml`, `service_pricing.yml` + `definitions/ServicePricing.yml`
- Comissionados: `agent_profiles.yml`, `agent_profile.yml` + `definitions/AgentProfile.yml`
- Fechamento: `period_closures.yml`, `period_closure.yml`, `period_closure_reopen.yml` + `definitions/PeriodClosure.yml`
- Relatórios (7): `reports_{top_procedures,revenue_vs_goal,revenue_by_procedure,revenue_by_payment_method,revenue_by_professional_table,account_statement,goals_vs_actual}.yml`
- Outros: `budget_simulate_plan.yml`, `dre_categories_restore_defaults.yml`

**Internal Chat — swagger novo (8):** `internal_chat_memberships.yml`, `internal_chat_membership.yml`, `internal_chat_typing.yml`, `internal_chat_attachments.yml`, `internal_chat_attachment_download.yml` + `definitions/Membership.yml`, `Attachment.yml`, `Sticker.yml`

**Narrativos (3)**
- `plugins/financial/README.md` (plugin não tinha README)
- `docs/02-architecture/ai-agent-architecture.md` (pipelines, catálogo de tools, providers, guardrail, RAG, crons, flags, models)
- `plugins/internal_chat/docs/realtime-and-bea.md` (eventos ActionCable + pipelines da Bea)

### 11.2 Atualizados (30)

**AI Agent (8):** `ai_agent_public.yml` (rating int, account_id, 429, health filtrado), `ai_agent_documents.yml`, `ai_agent_follow_up_rules.yml`, `ai_agent_internal_notification_template_{actions,reset}.yml`, `definitions/{Document,FollowUpRule,InternalNotificationTemplate}.yml` + comentário stale em `app/models/ai_agent/follow_up_rule.rb` (15min→1min)

**Financial (6):** `webhook_asaas.yml` (403 constante, remove 401/404), `revenue_goal.yml` (+get/+patch, delete 200), `revenue_goals.yml` (year→active, +403), `dre_category.yml` (regras de bloqueio do delete), `installment_pay.yml` (payment_method_id + modifiers type/value), `entries.yml` (filtro payment_method) + `definitions/RevenueGoal.yml`

**Internal Chat (11):** `internal_chat_rooms.yml` (add_bea, page/per_page, envelope data), `internal_chat_room.yml`, `internal_chat_room_actions.yml` (unread_summary, mute/unmute, +unarchive), `internal_chat_messages.yml`, `internal_chat_message.yml`, `internal_chat_message_actions.yml`, `internal_chat_mentions.yml`, `internal_chat_stickers.yml`, `internal_chat_sticker.yml` + `definitions/Message.yml`, `Room.yml`

**Índice e produto (3):** `swagger/plugins_index.yml` (7 tags + 2 tag-groups + 35 path `$ref`s + 9 definitions), `docs/01-product/modules/configuracoes.md` (RBAC real, fim das chaves `financial.*` fantasma), `docs/01-product/modules/financeiro-funcionamento.md` (PARTE 6.5 — 5 módulos novos)

### 11.3 Removidos (1)
- `plugins/financial/swagger/_index.yml.bak` (stub v1 morto descrevendo `/api/v1/financial/transactions`)

---

## 12. Correções de código (bugs além de documentação)

> A auditoria também encontrou defeitos reais de autorização/escopo (não apenas de doc). Corrigidos em 2026-05-30.

| Bug | Arquivo | Correção | Status |
|---|---|---|---|
| **`rename_provider` sem RBAC** — todas as escritas irmãs exigem ADMIN/GERENTE, mas essa ação (rename em massa de um provedor) não tinha gate | `payment_methods_controller.rb` | `rename_provider` e `destroy_provider` movidos para `before_action :authorize_write!` (ADMIN/GERENTE); removido o `authorize_write!` inline redundante de `destroy_provider` (evita render duplo) | ✅ |
| **super_admin `documents#destroy` cross-tenant** — `find` global por id; super_admin em uma conta podia apagar doc de OUTRA e a auditoria atribuía à conta errada | `app/controllers/super_admin/ai_agent_documents_controller.rb` | `find` agora scoped a `@account.documents_for_bea` (igual ao `index`) → 404 em vez de delete cross-tenant | ✅ |
| **Operações de caixa sem RBAC** — `installments#pay/refund` e `entries#create/update/destroy/bulk_reclassify` eram acessíveis a qualquer usuário autenticado | `installments_controller.rb`, `entries_controller.rb` | **Gate em camadas** (decisão de produto): receber/lançar/editar/reclassificar → **RECEPCAO/GERENTE/ADMIN**; estornar/excluir lançamento → **GERENTE/ADMIN**. Swagger correspondente atualizado com `403` + nota de role | ✅ |
| **Resíduo `dono` no preset ADMIN** — `base_controller.rb` mapeava `dono` (role removida em 2026-04-30) | `base_controller.rb` | **Removido.** Confirmado no banco: `KlivyRole.where(preset_key: 'dono').count == 0` (nenhum usuário afetado). Mapa agora `%w[admin administrator]` | ✅ Removido |

**Validação:** os controllers editados passam em `ruby -c` (Syntax OK). Teste ao vivo na conta 31 (não-mutante) confirmou o gate em camadas: recepcionista recebe `403` em `refund`/`rename_provider` mas passa em `pay`/`entries`; gerente/admin passam em tudo. Cada negação retorna `403 { error: forbidden, required_roles: [...] }` + `Financial::AuditLog` `denied`.
</content>
</invoke>
