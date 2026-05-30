# 09 — Checklist de Replicação

> Pra um programador replicar a feature de telemedicina **do zero** em outro sistema. Use isso como check-list — cada item é "feito" ou "não feito".

---

## Fase 0 — Pré-requisitos do ambiente

- [ ] Rails 7.1+ instalado.
- [ ] PostgreSQL 14+ (jsonb obrigatório).
- [ ] Redis 7+ (Sidekiq + ActionCable).
- [ ] Vue 3 + Vite no frontend.
- [ ] Pundit (autorização) — se não tem, considera permissões customizadas.
- [ ] ActiveRecord encryption configurado (`bin/rails db:encryption:init` em prod).
- [ ] ActionCable funcionando (WebSocket).
- [ ] Sidekiq rodando com queues `:high`, `:low`, `:purgable`.

---

## Fase 1 — Provisão de serviços externos

### LiveKit
- [ ] Conta criada (Cloud) **ou** self-host configurado (docker-compose ou kubernetes).
- [ ] API key + secret gerados.
- [ ] Webhook URL configurado: `https://<seudominio>/webhooks/livekit/egress`.
- [ ] TURN server funcional (Cloud já fornece; self-host requer config).

### Cloudflare R2
- [ ] Bucket criado (separado de qualquer outro storage).
- [ ] API token com `Read+Write` no bucket.
- [ ] Lifecycle rule: delete objetos após 30-90 dias (cobrir auditoria + custo).
- [ ] Endpoint URL copiado.

### Anthropic
- [ ] Conta API criada em `console.anthropic.com`.
- [ ] API key gerada.
- [ ] Limite mensal configurado (sugestão MVP: $200/mês).

### OpenAI
- [ ] Conta API.
- [ ] API key.
- [ ] Limite mensal (sugestão MVP: $300/mês).

### ENV vars no app
- [ ] `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.
- [ ] `TELEMED_STORAGE_BUCKET`, `TELEMED_STORAGE_ENDPOINT`, `TELEMED_STORAGE_ACCESS_KEY_ID`, `TELEMED_STORAGE_SECRET_ACCESS_KEY`.
- [ ] `ANTHROPIC_API_KEY`.
- [ ] `OPENAI_API_KEY`.
- [ ] `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` (+ deterministic + salt).

---

## Fase 2 — Gems Ruby + NPM

### Gemfile
- [ ] `gem 'livekit-server-sdk', '~> 0.9'`
- [ ] `gem 'jwt'`
- [ ] `gem 'aws-sdk-s3', require: false`
- [ ] `gem 'ruby_llm', '>= 1.8.2'`
- [ ] `gem 'ruby-openai'`
- [ ] `bundle install`

### package.json
- [ ] `livekit-client@^2.19.0`
- [ ] `@livekit/track-processors@^0.7.2` (opcional — blur de fundo)
- [ ] `vue-virtual-scroller` (transcrição longa)
- [ ] `@vueuse/components@^12.0.0`
- [ ] `date-fns@2.21.1` + `date-fns-tz@^1.3.3`
- [ ] `markdown-it` (resumo executivo)

---

## Fase 3 — Migrations (schema)

Crie as migrations seguindo [03-modelo-dados.md](03-modelo-dados.md). Ordem mínima:

- [ ] `create_telemed_recordings` — coluna principal: status, egress_ids, storage_keys, transcript_text (encrypted), transcript_segments (jsonb).
- [ ] `create_proposed_evolutions` — soap_structure, raw_markdown, summary, attention_points, procedure_fields (jsonb), status, reviewed_by.
- [ ] `create_telemed_consents` — patient consent LGPD.
- [ ] `add_procedure_fields_to_proposed_evolutions` (se separado).
- [ ] FK `proposed_evolution_id` na tabela de prontuário do seu sistema (no Klivy é `session_logs`).
- [ ] Indexes: `(account_id, created_at)`, `(status)`, `(telemed_recording_id, status='pending_review')` unique partial.

Validar:
```bash
bin/rails db:migrate
bin/rails db:schema:dump
```

---

## Fase 4 — Backend

### Models
- [ ] `TelemedRecording` com state machine (`pending → recording → ... → ready/failed`) e validação de transição.
- [ ] `encrypts :transcript_text`.
- [ ] `ProposedEvolution` com `encrypts :raw_markdown, :reviewer_notes, :summary`.
- [ ] `TelemedConsent` com método `accept!` idempotente.

### Services
- [ ] `Telemed::SessionIssuer` — JWT LiveKit (identity prefixada `doctor-X` / `patient-Y`).
- [ ] `Telemed::RecordingOrchestrator` — start! (cria 3 egress) + stop!.
- [ ] `Telemed::RecordingStorage` — wrapper AWS S3 client apontando pra R2.
- [ ] `Telemed::TranscriptionProvider` (factory) + impl `Gpt4oDiarize`.
- [ ] `Telemed::EvolutionProvider` (factory) + impl `Claude`.
- [ ] `Telemed::ProposedEvolutionApprovalService` — mapeia procedure_fields → SessionLog (atomic transaction).
- [ ] `Telemed::Session` — resolve estado (janela, bloqueios).
- [ ] `Telemed::SessionEventHandler` — joined/left → state machine.

### Controllers
- [ ] `Api::V1::Accounts::Telemed::SessionsController` — token, event, admit, recording on/off, confirm_completed.
- [ ] `Api::V1::Accounts::Telemed::TeleconsultasController` — index, show, counts, recording_url, retranscribe, reevolve.
- [ ] `Api::V1::Accounts::Telemed::ProposedEvolutionsController` — update, approve, reject. **Whitelist explícita** dos 14 procedure_fields keys.
- [ ] `Api::V1::PatientPortal::Telemed::SessionsController` — token + event (paciente).
- [ ] `Webhooks::Livekit::EgressController` — valida JWT + SHA-256 do body.

### Jobs
- [ ] `Telemed::TranscribeRecordingJob` (queue `:low`).
- [ ] `Telemed::GenerateEvolutionJob` (queue `:low`).
- [ ] `Telemed::MarkNoShowJob` (queue `:high`).
- [ ] `Telemed::MarkInProgressJob` (queue `:high`).
- [ ] `Telemed::EnforceRecordingQuotaJob` (queue `:purgable`).

### Routes
- [ ] `POST /webhooks/livekit/egress`.
- [ ] `resources :teleconsultas` (account-scoped).
- [ ] `resources :proposed_evolutions` (account-scoped).
- [ ] Session endpoints nested em `agenda_events`.
- [ ] Patient Portal endpoints (host-scoped).

### Policies (Pundit)
- [ ] `ProposedEvolutionPolicy` — show/update/approve/reject.
- [ ] Reusar `AgendaEventPolicy#telemedicine_join?`.

### Engine
- [ ] Injetar `has_many :telemed_recordings` em `Account`, `AgendaEvent`.
- [ ] Injetar `has_many :telemed_consents` em `Account`, `Patient`.

### Initializers
- [ ] Boot guard: fail-fast em prod se faltar `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`.

---

## Fase 5 — Frontend (Vue)

### Componente da sala (puro)
- [ ] `shared/components/TelemedicineRoom.vue` — usa `livekit-client`. Recebe props (url, token, role, requiresAdmit). Emite events (leave, session-event, ended-by-host).
- [ ] Suporta waiting room (canPublish toggle via permissions).
- [ ] Suporta blur de fundo (lazy-load `@livekit/track-processors`).
- [ ] Data channel pra `call_ended` broadcast.

### Dashboard
- [ ] `TeleconsultaListPage.vue` — paginação, abas, filtros.
- [ ] `TeleconsultaDetailPage.vue` — layout 2-cols + bloco full-width Procedure.
- [ ] `TeleconsultaRecordingPlayer.vue` — player áudio com R2 signed URL + refetch.
- [ ] `TeleconsultaTranscript.vue` — virtual scroller + karaokê sync ao player.
- [ ] `TeleconsultaSummary.vue` — render markdown.
- [ ] `TeleconsultaProcedureRegister.vue` — 14 campos + badges "IA" + checkbox responsabilidade + Salvar/Aprovar/Rejeitar.
- [ ] `TeleconsultaEvolutionEditor.vue` (lateral) — só pontos de atenção.
- [ ] `TelemedRoomPage.vue` (wrapper) — consome token, monta sala.

### Patient Portal
- [ ] `TelemedicineRoomPage.vue` (wrapper paciente).
- [ ] `TelemedicineJoinCard.vue` (inline no detalhe da consulta).

### API clients
- [ ] `dashboard/api/teleconsultas.js` — `TeleconsultasAPI` + `ProposedEvolutionsAPI`.
- [ ] `dashboard/api/agendaTelemedicine.js` — session endpoints.
- [ ] `patient/api/telemedicine.js` — paciente.

### Composables
- [ ] `useTeleconsultaList` — paginação + filtros + sequencer anti-stale.
- [ ] `useTelemedicineJoin` — pedir token + abrir popup.
- [ ] `useTelemedicineSession` (shared) — reportar joined/left idempotente.

### Routes
- [ ] `/teleconsultas` (lista).
- [ ] `/teleconsultas/:eventId` (detalhe).
- [ ] `/agenda/telemed/:eventId` (sala dentista, popup).
- [ ] Rotas paciente em host separado.

### SCSS
- [ ] `teleconsulta-index.scss` (lista).
- [ ] `teleconsulta-detail.scss` (detalhe).
- [ ] Sticky behavior no card de Pontos de Atenção.
- [ ] Karaokê na transcrição (`.is-active` highlight).

### ActionCable listener
- [ ] Listener global em `account_<id>` que re-emite eventos `telemed.*` via bus interno (mitt).
- [ ] `DetailPage` se inscreve em `TELEMED_RECORDING_UPDATED` → atualiza UI sem F5.

---

## Fase 6 — Testes e validação

### Smoke tests manuais (na ordem)

1. **Provisioning OK**:
   - [ ] Rails boota sem erro (com `RAILS_ENV=production` simula prod e checa boot guards).
   - [ ] Sidekiq processa jobs (verifica queues no painel).
   - [ ] ActionCable WebSocket conecta no browser.

2. **Sala de vídeo**:
   - [ ] Dentista clica "Entrar" → popup abre → vídeo aparece.
   - [ ] Paciente abre link → entra → ambos se veem.
   - [ ] Mic/cam controls funcionam.
   - [ ] Blur funciona.

3. **Waiting room**:
   - [ ] Paciente fora da janela tenta entrar → fica em "aguardando aceite".
   - [ ] Dentista clica "Admitir" → paciente publica mic/cam.

4. **Gravação**:
   - [ ] Dentista inicia gravação (manual ou auto) → status muda pra "Gravando".
   - [ ] Encerra → status vai pra "Processando".
   - [ ] Sidekiq processa TranscribeJob → status "Transcrevendo" → "Gerando evolução".
   - [ ] Fim: status "Aguarda revisão" + notification.

5. **Detalhe + revisão**:
   - [ ] Dashboard mostra teleconsulta finalizada.
   - [ ] Click → detalhe carrega.
   - [ ] Player toca o áudio (composite, do R2).
   - [ ] Transcrição mostra segmentos (com speaker labels).
   - [ ] Karaokê: rolar áudio → segmento atual destaca.
   - [ ] Resumo Executivo renderiza com negrito.
   - [ ] Pontos de Atenção aparecem na lateral.
   - [ ] Registrar Procedimento mostra 14 campos pré-preenchidos com badges "IA".

6. **Aprovação**:
   - [ ] Edita um campo → badge "IA" some daquele input.
   - [ ] Marca checkbox de responsabilidade.
   - [ ] Click "Salvar e Assinar" → confirm → API call → success.
   - [ ] Vai pra aba Pacientes > Bruna > Evolução > Ficha Clínica.
   - [ ] **Vê o SessionLog criado** com os dados da IA.

7. **Rejeição**:
   - [ ] Gerar nova evolução (via reevolve).
   - [ ] Click "Recusar" → modal pede justificativa.
   - [ ] Confirma → status: 'rejected'.
   - [ ] Auditoria salvou `reviewer_notes`.

### Testes automatizados sugeridos
- RSpec unit: cada service + cada job.
- Request specs: cada controller endpoint (happy path + 422 + 403).
- Vue tests: `TeleconsultaProcedureRegister.spec` (mount + edit field + submit).

---

## Fase 7 — Deploy

- [ ] Build production de frontend (`pnpm build`).
- [ ] Migrations rodadas em prod.
- [ ] ENV vars em todos os ambientes (CI, staging, prod).
- [ ] Secret rotation plan pra `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` (sem rotation, só backup seguro).
- [ ] Backup do bucket R2 documentado.
- [ ] Monitoring:
  - [ ] Sidekiq dead jobs alertam (Sentry/PagerDuty).
  - [ ] Webhook LiveKit failures alertam (4xx/5xx em `EgressController`).
  - [ ] Rate limit Anthropic/OpenAI logado.
- [ ] Rollback plan: feature flag `telemedicine_enabled` por conta (defaults `false`).

---

## Fase 8 — Documentação interna

- [ ] CHANGELOG entry pra cada release de fix.
- [ ] Runbook ops:
  - "Webhook LiveKit não chega" — checar URL no painel + rotear via ngrok pra debug.
  - "Transcrição falhou" — re-enfileirar `TranscribeRecordingJob`.
  - "Evolução ruim" — re-enfileirar `GenerateEvolutionJob`.
  - "Gravação > 25MB" — chunking não implementado, falha permanente.
- [ ] Treinamento da equipe (CS/Suporte) pra triar problemas.

---

## Decisões críticas a tomar antes de codar

### Áudio-only ou vídeo gravado?
Klivy escolheu audio-only (LGPD + custo). Se quiser vídeo, troca `RoomCompositeEgress` config (mas re-validar LGPD com jurídico).

### Modelo de IA?
Default `claude-sonnet-4-6` (qualidade PT-BR). Trocar via setting ou hardcode no `EvolutionProvider::DEFAULT_PROVIDER`.

### Modelo de transcrição?
Default `gpt-4o-transcribe-diarize` (WER 2.46%, diarização nativa). Trocar pra Whisper se custo crítico.

### Prontuário target?
Klivy: `SessionLog` (modelo unificado). Se seu sistema usa outro nome (ClinicalNote, MedicalRecord), ajustar `ProposedEvolutionApprovalService#build_session_log` + FK migration.

### Provedor de storage?
Klivy: Cloudflare R2 (S3-compat). Funciona com AWS S3, GCS (S3 emulation), MinIO. Trocar endpoint + creds, código é o mesmo.

### LiveKit self-host ou Cloud?
Cloud pra MVP (zero infra). Self-host quando volume passar de ~500h/mês (custo/benefício inverte).

---

## TL;DR — Esforço estimado

| Fase | Estimativa (programador sênior) |
|------|---------------------------------|
| 0 — Pré-reqs | 2 dias (assumindo Rails 7 já está rodando) |
| 1 — Provisioning | 1 dia |
| 2 — Gems + NPM | 0.5 dia |
| 3 — Migrations | 0.5 dia |
| 4 — Backend completo | 5-7 dias |
| 5 — Frontend completo | 7-10 dias |
| 6 — Testes + bugfix | 3-5 dias |
| 7 — Deploy | 1-2 dias |
| **TOTAL** | **~20-28 dias úteis** |

Replicação literal (copy/adapt) é mais rápido (~10-15 dias) se o sistema-destino tem stack similar (Rails 7 + Vue 3).
