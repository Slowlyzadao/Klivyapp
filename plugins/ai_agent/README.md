# AI Agent (Bea) — Klivy plugin

Single-agent virtual assistant para clínicas brasileiras. **Bea** é a recepcionista IA que responde pacientes via WhatsApp (e futuramente outros canais), agenda consultas, dispara follow-ups proativos e notifica a equipe via Chat Interno quando precisa de intervenção humana.

## Arquitetura em 1 página

```
                    ┌──────────────────────────────────────┐
                    │  WhatsApp / Webhook do Chatwoot      │
                    └─────────────────┬────────────────────┘
                                      │ Message#after_create_commit
                                      ▼
                    ┌──────────────────────────────────────┐
                    │ AiAgent::ChatResponseJob (Sidekiq)   │
                    │  - coalescing                        │
                    │  - idempotency (Trace unique index)  │
                    │  - audio transcription, visual handoff│
                    └─────────────────┬────────────────────┘
                                      │
                                      ▼
                    ┌──────────────────────────────────────┐
                    │ AiAgent::ChatService (orchestrator)  │
                    │  guards → emergency → captain quota  │
                    │  → escalation → state machine        │
                    │  → LLM (Gemini/OpenAI w/ tools)      │
                    │  → guardrail → sentinel → trace      │
                    └─────────────────┬────────────────────┘
                                      │
                          ┌───────────┴───────────┐
                          ▼                       ▼
              ┌─────────────────────┐   ┌─────────────────────┐
              │ Tools (LLM-called)  │   │ Trace (telemetry)   │
              │  - search_slots     │   │  - cost, latency,   │
              │  - book/reschedule  │   │    escalations,     │
              │  - create_patient   │   │    guardrail viols  │
              │  - transfer_to_human│   └─────────────────────┘
              └─────────────────────┘
```

## Componentes principais

| Componente | Responsabilidade |
|---|---|
| [ChatService](app/services/ai_agent/chat_service.rb) | Orquestrador de turn — guards, emergency, deterministic confirmations, LLM, guardrail, trace |
| [ChatResponseJob](app/jobs/ai_agent/chat_response_job.rb) | Worker Sidekiq que dispara ChatService por mensagem incoming |
| [ConfigResolver](app/services/ai_agent/config_resolver.rb) | 3-layer config (global → account → user) com cost cap enforcement |
| [Emergency::Detector](app/services/ai_agent/emergency/detector.rb) | Classificador determinístico keyword PT-BR (SAMU 192 / CVV 188) — runs ANTES do LLM |
| [Guardrail::Validator](app/services/ai_agent/guardrail/validator.rb) | Filtro pós-LLM contra diagnóstico médico, prescrição, garantias clínicas |
| [Humanization::Sentinel](app/services/ai_agent/humanization/sentinel.rb) | Reflection 1-step LLM-as-judge em turnos high-stakes (opt-in) |
| [RAG::Retriever](app/services/ai_agent/rag/retriever.rb) | Vector search em KB da conta (pgvector IVFFlat) |
| Tools (`app/services/ai_agent/tools/*`) | search_available_slots, book_appointment, create_patient_minimal, transfer_to_human, etc |
| Jobs cron | FollowUpDispatcherJob (1min), ConsolidatePatientMemoryJob (4h SP diário), ProactiveOutreachJob (14h SP diário), Health::MonitorJob (10min) |

## Domínio crítico (multi-tenant)

**Toda query, broadcast e Redis key DEVE ser scoped por `account_id`.** Bea é multi-tenant — múltiplas clínicas no mesmo deploy, cada uma com seu próprio AccountSetting, KB documents, FollowUpRules. Ver [AGENTS.md → Multi-tenancy](../../AGENTS.md#multi-tenancy--toda-feature-roda-em-isolamento-por-account_id).

Vetores de cross-tenant historicamente vulneráveis:
- LLM tools que recebem IDs do modelo (validar account_id no escopo)
- Broadcasts ActionCable (user.pubsub_token é único por user, mas account_id no payload é guard)
- Background jobs que aceitam IDs (passar `account_id:` como kwarg obrigatório)
- RAG vector retrieval (filter `account_id` no scope, não só post-fetch)

Ver [audit 2026-05-18](../../docs/audits/ai-agent-internal-chat-audit.md) para histórico de findings + remediações.

## Documentação

- [Plano de configuração de Bea](../../docs/01-product/ai-agent-configuration-plan.md) — overview de produto, Sprint H/I roadmap
- [PRD chat interno](../../docs/01-product/modules/PRD-chat-interno.md) — integração Bea ↔ Chat Interno staff
- [ADRs](../../docs/adr/) — decisões arquiteturais (LLM fallback, Sentinel opt-in, etc.)
- [Audit técnico 2026-05-18](../../docs/audits/ai-agent-internal-chat-audit.md) — review enterprise (171 findings, 121 aplicados)

## Decisões pesadas

| Decisão | ADR | Resumo |
|---|---|---|
| LLM provider primário + fallback | [0001](../../docs/adr/0001-llm-provider-fallback.md) | Gemini primary → OpenAI fallback após N falhas. Circuit breaker Redis |
| Sentinel opt-in | [0002](../../docs/adr/0002-sentinel-opt-in.md) | LLM-as-judge desativado por padrão (custo 2× LLM) |
| Read receipts via Membership.last_read_message_id | [0003](../../docs/adr/0003-read-receipts-membership-only.md) | Sem tabela ReadReceipt dedicada — simpler model |

## Testing

```bash
# Spec suite completa do plugin
docker compose exec rails bundle exec rspec plugins/ai_agent/spec

# Specs caracterizadores principais (BE-1, BE-2 do audit)
docker compose exec rails bundle exec rspec \
  plugins/ai_agent/spec/services/ai_agent/chat_service_spec.rb \
  plugins/ai_agent/spec/jobs/ai_agent/chat_response_job_spec.rb
```

Atual: **120 examples, 0 failures** (revisão 2026-05-19).
