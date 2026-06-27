# Guia de Replicação — Telemedicina, Área do Paciente e Documentos

> Documento para o desenvolvedor replicar três módulos do KlivyApp no projeto dele.
> Diz **onde fica cada pasta**, **o que cada uma faz**, **como tudo se conecta** e o **passo a passo** pra funcionar.
> Caminhos são relativos à raiz do projeto (`/`).

---

## 0. LEIA PRIMEIRO — Como o sistema de plugins funciona

Todo módulo do Klivy é um **Rails Engine** dentro de `plugins/<nome>/`. Entender este encanamento evita 90% dos erros de replicação.

### 0.1 Como os plugins são carregados (backend)
- Carregamento automático em **`config/application.rb:59`**:
  ```ruby
  Dir[Rails.root.join('plugins/*/lib/*/engine.rb')].each { |f| require f }
  ```
  Esse `require` apenas **define** a classe `<Plugin>::Engine < ::Rails::Engine`. Por herdar de `Rails::Engine`, o Rails **auto-registra** a engine e, **por convenção**, adiciona sozinho ao app: `app/models`, `app/controllers`, `app/services`, `app/jobs`, `app/policies`, `app/serializers`, `app/mailers`, `app/views`, `config/routes.rb`, `config/locales` e `db/migrate`. **Por isso os `engine.rb` são curtos** — não precisa configurar paths à mão.
- Cada plugin tem `plugins/<nome>/lib/<nome>.rb` que faz `require '<nome>/engine'`.
- O que os `engine.rb` realmente fazem é **injetar associações no core** via `config.to_prepare` (ex.: `Account.has_many :telemed_recordings`). Sempre com guarda `if defined?(Model)`.

### 0.2 Montagem das rotas é no HOST, não no engine
As rotas são montadas no arquivo raiz **`config/routes.rb`** com `mount <Plugin>::Engine, at: '/'`. As rotas reais ficam em `plugins/<nome>/config/routes.rb`. **Plugin novo precisa das duas coisas**: o `mount` no host + o `routes.rb` no plugin.

### 0.3 Migrations (PEGADINHA IMPORTANTE)
- Na **maioria** dos plugins (telemed, patient_portal, document_templates, signatures, patients, agenda, financial), as migrations **NÃO ficam** em `plugins/<nome>/db/migrate/` (esses diretórios estão **vazios**). Elas ficam **todas em `db/migrate/` da raiz**. Um `rails db:migrate` normal pega tudo.
- Exceções: apenas `custom_roles` e `migration` guardam migrations dentro do próprio plugin e fazem `append` via initializer.

### 0.4 Como o frontend dos plugins entra no build (NÃO há auto-discovery)
- Os frontends são puxados por **imports explícitos** via o alias **`@plugins` → `./plugins`** (definido em `vite.config.ts:110`).
- **Adicionar um plugin ao dashboard = editar manualmente 5 arquivos do core:**
  | Arquivo | O que registrar |
  |---|---|
  | `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | `import { routes } from '@plugins/<p>/frontend/.../routes'` + `...spread` em `children` |
  | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | o item da aba no `menuItems` + entrada em `SIDEBAR_NAME_TO_MODULE` (RBAC) |
  | `app/javascript/dashboard/i18n/locale/{en,pt_BR}/index.js` | import dos JSONs de `@plugins/<p>/frontend/i18n` |
  | `app/javascript/dashboard/store/index.js` | módulos Vuex do plugin (se houver) |
  | `app/javascript/dashboard/helper/routeHelpers.js` | regras RBAC (`KLIVY_*_ROUTE_RULES`) — **esquecer isto deixa a rota acessível por URL direta sem permissão** |
- HMR depende de `config/vite.json` → `watchAdditionalPaths: ["plugins/**/*"]`.
- **O Portal do Paciente é um SPA SEPARADO** (Vue 3 + Pinia, não o Vuex do dashboard), com entrypoint próprio `app/javascript/entrypoints/patient_portal.js` → `plugins/patient_portal/frontend/main.js`.

### 0.5 `isolate_namespace` é inconsistente DE PROPÓSITO
- **USAM** namespace isolado: `beclinic_core`, `patients`, `billing`, `financial` (ex.: `Financial::Expense`).
- **NÃO usam** (models no namespace global): `agenda`, `telemed`, `patient_portal`, `document_templates`, `signatures` (ex.: `TelemedRecording`, `DocumentTemplate`, `SignatureRequest`). Ao criar plugin, siga o vizinho do mesmo domínio.

### 0.6 Grafo de dependência entre plugins (ordem de instalação)
```
beclinic_core            (base de tudo — permissões can(module,action), perfis)
   └── patients          (Patient, ClinicalNote, Document, ConsentRecord)
   └── agenda            (AgendaEvent)
   └── financial         (Installment, Budget, GatewaySetting)
         ├── document_templates → depende de: patients, beclinic_core
         │      └── signatures  → depende de: patients, document_templates
         ├── patient_portal     → depende de: patients, agenda, financial, beclinic_core
         └── telemed            → depende de: agenda, patients, patient_portal, beclinic_core
```
**Bases compartilhadas obrigatórias:** `beclinic_core` (sistema de permissões usado pela sidebar inteira), `patients` (dono dos models clínicos), `agenda` (dono do `AgendaEvent`).

---

# MÓDULO 1 — TELEMEDICINA

**O que entrega:** teleconsulta por vídeo (LiveKit) de ponta a ponta — sala com sala de espera, automação de status do agendamento, gravação **só de áudio** (LiveKit Egress → R2), transcrição (OpenAI Whisper / gpt-4o-transcribe-diarize), evolução clínica SOAP gerada por IA (Claude via `ruby_llm`) e aprovação que vira prontuário (`SessionLog`). Status em tempo real via ActionCable.

## 📍 Localização
`plugins/telemed/`

## 🌳 Estrutura de pastas

**Backend**
- `plugins/telemed/lib/telemed/` — `engine.rb` (injeta `has_many telemed_recordings/telemed_consents` em Account/Patient/AgendaEvent) e `telemed.rb`.
- `plugins/telemed/config/` — `routes.rb` da engine (webhook LiveKit + namespaces `telemed` admin e paciente).
- `plugins/telemed/db/migrate/` — **VAZIO** (migrations estão na raiz `db/migrate/`).
- `plugins/telemed/app/models/` — `telemed_recording.rb`, `proposed_evolution.rb`, `telemed_consent.rb`.
- `plugins/telemed/app/controllers/api/v1/accounts/telemed/` — API da clínica: `teleconsultas_controller`, `sessions_controller`, `proposed_evolutions_controller`.
- `plugins/telemed/app/controllers/api/v1/patient_portal/telemed/` — API do paciente: `sessions_controller` (token role=patient, joined/left, consent).
- `plugins/telemed/app/controllers/webhooks/livekit/` — `egress_controller.rb` (recebe webhooks LiveKit, valida JWT HS256, dispara transcrição).
- `plugins/telemed/app/services/telemed/` — domínio: `Session`, `SessionIssuer` (JWT), `CredentialsResolver`, `RoomCode`, `RecordingOrchestrator`, `RecordingStorage`, `ParticipantAdmitter`, `AdmissionWindow`, `SessionTracker`, `SessionEventHandler`, `SessionJobScheduler`, `StatusTransition`, `ProposedEvolutionApprovalService`, `PermanentFailure`.
- `plugins/telemed/app/services/telemed/transcription_provider/` — `whisper.rb`, `gpt4o_diarize.rb`.
- `plugins/telemed/app/services/telemed/evolution_provider/` — `claude.rb` (padrão), `open_ai.rb` (fallback).
- `plugins/telemed/app/jobs/telemed/` — `transcribe_recording_job`, `generate_evolution_job`, `mark_in_progress_job`, `mark_no_show_job`, `enforce_recording_quota_job`, `purge_account_recordings_job`.
- `plugins/telemed/app/policies/` — `proposed_evolution_policy.rb`.

**Frontend**
- `plugins/telemed/frontend/shared/` — `TelemedicineRoom.vue` (sala WebRTC `livekit-client`, compartilhada), `TelemedDeviceSelect.vue`, `useTelemedicineSession.js`.
- `plugins/telemed/frontend/dashboard/` — visão da clínica: `routes/routes.js`, `pages/TelemedRoomPage.vue`, `features/teleconsulta/*` (List/Detail/Card/EvolutionEditor/RecordingPlayer/Transcript/Summary/ProcedureRegister), `api/`, `composables/`.
- `plugins/telemed/frontend/patient/` — visão do paciente: `pages/TelemedicineRoomPage.vue`, `components/TelemedicineJoinCard.vue`, `api/telemedicine.js`, `routes/` (montadas pelo router do portal).
- `plugins/telemed/frontend/styles/` — `teleconsulta-detail.scss`, `teleconsulta-index.scss`.

**Apoio**
- `plugins/telemed/dev-tools/` — configs de dev do LiveKit (`livekit-server/config.yaml`, `livekit-egress/config.yaml`).
- `plugins/telemed/bin/` — `dev-bootstrap` (cria bucket MinIO, escreve `tmp/telemed-tunnels.json`).
- `plugins/telemed/docs/` — `prd.md`, `audit.md`, `agenda-integration.md`.

## 🔑 Arquivos-chave
- `plugins/telemed/lib/telemed/engine.rb` — injeta associações no core (via `to_prepare`). **NÃO** declara mais `ClinicalNote.belongs_to :proposed_evolution` (removido na Fase 4 do audit; navegação reversa é por query).
- `plugins/telemed/app/models/telemed_recording.rb` — state machine `pending→recording→uploaded→transcribing→transcribed→evolving→ready/failed`, `encrypts :transcript_text`, `archive!` (deleta do R2), broadcast ActionCable.
- `plugins/telemed/app/models/proposed_evolution.rb` — SOAP/summary/procedure_fields, `encrypts` campos PII, `approve!`/`reject!`/`apply_edit!`.
- `plugins/telemed/app/services/telemed/session_issuer.rb` — emite JWT LiveKit; paciente entra com `canPublish=false` (sala de espera). `room_name = klivy-acc<accId>-event<evId>`.
- `plugins/telemed/app/services/telemed/recording_orchestrator.rb` — dispara 3 Egress só-áudio (doctor/patient/composite, OGG opus 64kbps) → upload S3/R2.
- `plugins/telemed/app/controllers/webhooks/livekit/egress_controller.rb` — valida JWT HS256, persiste storage keys, enfileira `TranscribeRecordingJob`.
- `plugins/telemed/app/jobs/telemed/transcribe_recording_job.rb` — baixa do R2, pré-processa com **ffmpeg**, transcreve, enfileira evolução. Fila `:low`.
- `plugins/telemed/app/jobs/telemed/generate_evolution_job.rb` — monta contexto do paciente, chama Claude, cria `ProposedEvolution(pending_review)`. Fila `:low`.
- `plugins/telemed/app/services/telemed/evolution_provider/claude.rb` — `ruby_llm`+Anthropic (`claude-sonnet-4-6`), gera SOAP + Resumo + 14 campos de Registro de Procedimento.
- `config/initializers/telemed.rb` — em produção exige `ACTIVE_RECORD_ENCRYPTION_*` (LGPD) ou `TELEMED_ALLOW_UNENCRYPTED=true`.

## 🗄️ Migrations (em `db/migrate/` da raiz — 11)
```
20260520000001_create_telemed_recordings.rb
20260520000002_create_proposed_evolutions.rb
20260520000004_add_telemedicine_recording_to_patient_portal_settings.rb   (compartilhada c/ portal)
20260520000005_add_audio_only_telemed_columns.rb
20260521000001_create_telemed_consents.rb
20260521000002_migrate_telemedicine_recording_consents.rb
20260521000003_add_telemed_audit_phase2_indexes.rb
20260521000004_add_proposed_evolution_uniqueness_guard.rb
20260522000001_add_summary_to_proposed_evolutions.rb
20260526000001_add_procedure_fields_to_proposed_evolutions.rb
20260526000002_add_proposed_evolution_id_to_session_logs.rb
```
Dependem de tabelas já existentes: `accounts`, `agenda_events`, `patients`, `clinical_notes`, `session_logs`, `patient_portal_settings`.

## 🛣️ Rotas
- **Clínica:** `/api/v1/accounts/:account_id/telemed/*` — `teleconsultas` (+ `counts`, `:id/recording_url`, `:id/retranscribe`, `:id/reevolve`), `proposed_evolutions/:id` (+ `approve`/`reject`), `sessions` (+ `event`/`admit_patient`/`start_recording`/`stop_recording`/`confirm_completed`).
- **Paciente:** `/api/v1/patient_portal/telemed/sessions` (+ `event`) — `account_id` vem do JWT do portal.
- **Webhook:** `POST /webhooks/livekit/egress`.
- **Frontend dashboard:** `/app/accounts/:accountId/teleconsultas` (lista), `.../teleconsultas/:eventId` (detalhe), `.../agenda/telemed/:eventId` (sala).
- **Frontend paciente:** `/appointments/:id/telemed`.

## 🔌 Wiring de frontend (o que editar no core)
- `dashboard.routes.js`: `import { routes as telemedRoutes } from '@plugins/telemed/frontend/dashboard/routes/routes'` + `...telemedRoutes`.
- `Sidebar.vue`: item **'Teleconsulta'** (`i-lucide-video`, `to: accountScopedRoute('teleconsultas_index')`); no mapa de RBAC, **Teleconsulta → módulo `agenda`** (reusa a permissão da Agenda).
- Router do portal (`plugins/patient_portal/frontend/router/index.js`): rota `/appointments/:id/telemed` → `@plugins/telemed/frontend/patient/pages/TelemedicineRoomPage.vue`.

## 🧩 Depende dos plugins
`agenda` (AgendaEvent é a entidade central; reusa `AgendaEventPolicy`), `patients` (Patient/ClinicalNote/SessionLog), `patient_portal` (setting de gravação + base controller do paciente + SPA), `beclinic_core` (RBAC).

## 📦 Dependências
- **Gems:** `livekit-server-sdk (~> 0.9)`, `ruby_llm (>= 1.8.2)`, `ruby_llm-schema`, `ruby-openai`, `aws-sdk-s3 (require: false)`, `jwt`.
- **npm:** `livekit-client (^2.19.0)`, `@livekit/track-processors (^0.7.2)`.

## 🔐 Variáveis de ambiente
| Variável | Para quê |
|---|---|
| `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | Servidor LiveKit + tokens + validação do webhook |
| `LIVEKIT_EGRESS_URL` | (opcional) base do Egress/RoomService |
| `OPENAI_WHISPER_KEY` | Transcrição (billing isolado do Captain) |
| `ANTHROPIC_API_KEY` | Evolução SOAP (Claude) |
| `OPENAI_API_KEY` | Fallback de evolução (gpt-4o) |
| `TELEMED_STORAGE_BUCKET/ENDPOINT/REGION/ACCESS_KEY_ID/SECRET_ACCESS_KEY` | Storage R2/S3 das gravações (fallback para os `STORAGE_*`) |
| `TELEMED_STORAGE_INTERNAL_ENDPOINT` | (dev) endpoint visto de dentro do container Egress |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` / `_DETERMINISTIC_KEY` / `_KEY_DERIVATION_SALT` | **Obrigatórias em produção** (criptografa transcrição/evolução — LGPD/CFM) |
| `TELEMED_ALLOW_UNENCRYPTED=true` | Bypass intencional do guard de criptografia (sem dados reais) |

## ☁️ Serviços externos
LiveKit (servidor WebRTC) · LiveKit Egress (gravação) · Cloudflare R2 / S3 · OpenAI (transcrição) · Anthropic (evolução) · Redis · MinIO (dev) · cloudflared (dev).

## ✅ Passo a passo
1. **Gems** no Gemfile (lista acima) → `bundle install`.
2. **npm**: instalar `livekit-client` e `@livekit/track-processors`.
3. **Engine**: nada a registrar — `config/application.rb` carrega automaticamente. Conferir `config/initializers/telemed.rb`.
4. **Migrations**: copiar as 11 da raiz `db/migrate/` → `rails db:migrate`.
5. **Frontend**: editar `dashboard.routes.js`, `Sidebar.vue` (item + RBAC `agenda`) e o router do portal.
6. **ENV**: setar LiveKit, storage, OpenAI, Anthropic; em produção, as 3 chaves `ACTIVE_RECORD_ENCRYPTION_*`.
7. **Habilitar por conta**: `patient_portal_settings.telemedicine_recording` `{enabled:true, ai_provider:'claude-sonnet-4.6', patient_consent_required:true, max_active_recordings:15}` e `telemedicine_enabled:true` em `AgendaEvent.custom_attributes`.
8. **Infra**: subir LiveKit + Egress + Redis; configurar webhook do LiveKit → `POST /webhooks/livekit/egress`; garantir **ffmpeg** nos workers.
9. **Sidekiq**: filas `:low` (transcribe/evolution), `:high` (status), `:purgable` (quota/purge) ativas.
10. **Dev local**: usar `plugins/telemed/dev-tools/` e rodar `plugins/telemed/bin/dev-bootstrap`.

---

# MÓDULO 2 — ÁREA DO PACIENTE (PATIENT PORTAL)

**O que entrega:** um **SPA separado** (Vue 3 + Pinia) servido em subdomínio (`pacientes.*`) com login OTP por JWT, home, agendamento, documentos, anamnese, consentimentos com assinatura, teleconsulta, financeiro read-only, **pagamento online via Asaas**, mensageria reusando o Chatwoot, notificações + **Web Push (PWA)**, dependentes/responsável legal e cobranças automáticas de no-show/cancelamento. Inclui um painel admin de configuração dentro do dashboard da clínica.

## 📍 Localização
- `plugins/patient_portal/` (engine + SPA)
- `app/javascript/entrypoints/patient_portal.js` (entrypoint Vite do SPA)
- `app/javascript/dashboard/routes/dashboard/settings/patient_portal/` (painel admin no dashboard)

## 🌳 Estrutura de pastas

**Backend**
- `plugins/patient_portal/lib/patient_portal/` — `engine.rb` (injeta associações em Account/Patient/User + hook `after_update_commit` em AgendaEvent → `NoShowFeeAssessor`).
- `plugins/patient_portal/config/` — `routes.rb` (API do paciente + API admin + catch-all do SPA por host).
- `plugins/patient_portal/app/controllers/api/v1/patient_portal/` — API do SPA (auth JWT próprio, **sem Devise**): `base_controller`, `auth_controller` (OTP), `home`, `appointments`, `appointment_requests`, `documents`, `document_requests`, `financial`, `payments`, `messages`, `notifications`, `profile`, `consents`, `consent_records`, `anamneses`, `dependents`, `push_subscriptions`, `recall`, `lgpd_exports`, `preflight`.
- `plugins/patient_portal/app/controllers/api/v1/accounts/patient_portal/` — API admin (Devise + `ensure_admin!`): `invites`, `settings` (+ `apply_preset`), `portal_suspensions`.
- `plugins/patient_portal/app/controllers/` (raiz) — `patient_portal_pages_controller.rb` (renderiza o shell HTML do SPA), `patient_portal_diag_controller.rb` (diagnóstico dev).
- `plugins/patient_portal/app/models/` — `PatientPortalSetting`, `ProfessionalPortalSetting`, `PatientPortalOtp`, `PatientPortalSession`, `PatientPortalAccessLog`, `PatientPortalConsent`, `PatientPortalNotification`, `PatientPortalPushSubscription`, `PortalInvite`, `PortalAppointmentRequest`, `PortalDocumentRequest`, `PortalPayment`, `PatientResponsibleLink`.
- `plugins/patient_portal/app/services/patient_portal/` — `Authenticator`, `JwtEncoder`, `OtpDispatcher`, `SessionContext`, `*Visibility`, `FinancialSummary`, `ConfigResolver`/`PresetApplier`, `MessagingBridge` (ponte Chatwoot), `NotificationDispatcher`/`PushNotifier`, `PortalPaymentReconciler` (webhook Asaas), `PreflightChecker`.
- `plugins/patient_portal/app/services/patient_portal/payment/` — `gateway.rb` (factory), `asaas_gateway.rb` (real), `mock_gateway.rb` (dev).
- `plugins/patient_portal/app/services/patient_portal/fees/` — `calculator`, `fee_issuer`, `late_cancel_fee_assessor`, `no_show_fee_assessor`.
- `plugins/patient_portal/app/jobs/patient_portal/` — `send_push_job.rb`.
- `plugins/patient_portal/app/mailers/patient_portal/` + `app/views/patient_portal/otp_mailer/` — envio de OTP por email.
- `plugins/patient_portal/app/views/patient_portal_pages/` — `index.html.erb` (shell HTML do SPA).

**Frontend (o SPA)**
- `plugins/patient_portal/frontend/main.js` — bootstrap (createApp + Pinia + Router, monta `#patient-portal-app`).
- `plugins/patient_portal/frontend/pages/` — 23 páginas Vue (Login, OtpVerify, AccountSelect, ConsentTerms, Home, Appointments, NewAppointment, Health, DocumentRequest, Anamnesis, Financial, Payment, ConsentRecords, ConsentSign, Notifications, Messages, Profile…).
- `plugins/patient_portal/frontend/store/` — stores Pinia (`auth`, `appointments`, `documents`, `financial`, `messages`, `notifications`, `payments`, `profile`, `push`…).
- `plugins/patient_portal/frontend/api/` — clientes HTTP (`http.js` injeta Bearer JWT, base URL relativa).
- `plugins/patient_portal/frontend/components/` + `components/icons/` — UI (AppShell, BottomNav, SideNav, OtpInput, SignaturePad, QrCanvas, PushSubscriptionToggle, KlivyLogo) + ~30 ícones SVG.
- `plugins/patient_portal/frontend/router/` — `index.js` (history mode + guard de auth/consent; rota telemed importa `@plugins/telemed`).
- `plugins/patient_portal/frontend/styles/`, `utils/`, `composables/`, `assets/logo/`.

**Painel admin (dentro do dashboard)**
- `app/javascript/dashboard/routes/dashboard/settings/patient_portal/` — `patient_portal.routes.js` + `Index.vue` + `PresetCard`/`SettingSection`/`KeyValueRow.vue`.

## 🔑 Arquivos-chave
- `plugins/patient_portal/lib/patient_portal/engine.rb` — injeta associações + `Patient#portal_active?` + hook de no-show fee.
- `plugins/patient_portal/config/routes.rb` — 3 superfícies (API paciente, API admin, catch-all do SPA por host).
- `.../api/v1/patient_portal/base_controller.rb` — auth JWT (decodifica Bearer, resolve `PatientPortalSession` por `jti`, separa acting vs active patient para dependentes).
- `.../services/patient_portal/jwt_encoder.rb` — JWT HS256 com `Rails.application.secret_key_base`.
- `.../services/patient_portal/payment/asaas_gateway.rb` — Asaas real (clientes + cobranças PIX/boleto/cartão); credenciais vêm de `Financial::GatewaySetting` **no banco** (não é env var).
- `.../services/patient_portal/portal_payment_reconciler.rb` — reconcilia webhook Asaas → marca `PortalPayment` paga.
- `.../services/patient_portal/messaging_bridge.rb` — usa Inbox/Conversation/Message do Chatwoot (sem models novos).
- `.../services/patient_portal/push_notifier.rb` — Web Push com VAPID.
- `config/initializers/vapid_keys.rb` — lê `VAPID_*` do ENV (ou gera par efêmero em dev).
- `app/javascript/entrypoints/patient_portal.js` — entrypoint Vite → `plugins/patient_portal/frontend/main.js`.
- `public/patient_portal_sw.js` + `public/patient_portal_manifest.webmanifest` — service worker e manifest PWA (já em `public/`).

## 🗄️ Migrations (em `db/migrate/` da raiz)
```
20260518000001_create_patient_portal_settings.rb
20260518000002_create_professional_portal_settings.rb
20260518000003_create_portal_invites.rb
20260518000004_create_patient_portal_otps.rb
20260518000005_create_patient_portal_sessions.rb
20260518000006_create_patient_portal_access_logs.rb
20260518000007_add_portal_columns_to_patients.rb
20260518000008_create_patient_portal_consents.rb
20260518000009_create_portal_appointment_requests.rb
20260518000010_create_portal_document_requests.rb
20260518000011_create_patient_portal_notifications.rb
20260518000012_create_portal_payments.rb
20260518000013_create_patient_portal_push_subscriptions.rb
20260518000014_create_patient_responsible_links.rb
20260518000015_add_active_patient_to_portal_sessions.rb
20260520000004_add_telemedicine_recording_to_patient_portal_settings.rb
20260307200016_create_consent_records.rb
20260311231432_add_body_and_document_type_to_consent_records.rb
20260503190100_backfill_consent_signed_status.rb
20260511190100_backfill_patient_responsible_professional.rb
20260527000004_add_template_ref_to_consent_records.rb
```

## 🛣️ Rotas
- **API paciente:** `/api/v1/patient_portal/*` — `auth/{request_otp,verify_otp,select_account,logout,me}`, `home`, `consents/*/accept`, `notifications`, `messages` (+ `triage`), `profile`, `lgpd/exports`, `payments` (+ `cancel`), `push_subscriptions`, `dependents`, `appointments`, `appointment_requests`, `documents`, `document_requests`, `financial/*`, `consent_records` (+ `sign`), `anamneses`, `recall/*`.
- **API admin:** `/api/v1/accounts/:account_id/patient_portal/*` — `invites`, `setting` (+ `apply_preset`), `portal_suspension`.
- **SPA:** `root` e catch-all `GET /*params` → `patient_portal_pages#index`, **só quando o host casa** `pacientes.*` / `*.localhost` / túneis **E** o path não começa com prefixos do dashboard (`/app /auth /api …`).
- **Produção:** `pacientes.klivy.app`. **Dev:** `pacientes.lvh.me:3000` ou `pacientes.localhost:3000`.
- **Painel admin (dashboard):** `/app/accounts/:accountId/settings/patient-portal`.

## 🔌 Wiring de frontend
- O SPA é um **entrypoint Vite separado** (auto-descoberto pelo `vite-plugin-ruby`, sem registro manual): `patient_portal.js` → `main.js`. **Não entra no bundle do dashboard nem na sidebar do dashboard.**
- O HTML é servido pela view ERB `patient_portal_pages/index.html.erb` (monta `#patient-portal-app`, injeta `window.klivyPatientPortalConfig`).
- `config/vite.json` precisa de `watchAdditionalPaths: ["plugins/**/*"]`.
- O **painel admin** (esse sim) entra no dashboard: `settings.routes.js` importa `patient_portal.routes.js`.

## 🧩 Depende dos plugins
`patients`, `agenda`, `financial` (Installment/Budget/GatewaySetting), `beclinic_core`, `consent_records`/`ConsentRecord`, `anamnesis`, `document_templates` (`form_template_id` em consent_records), `telemed` (sala importada na rota).

## 📦 Dependências
- **Gems:** `jwt`, `web-push (>= 3.0.1)`.
- **npm:** `vue (3)`, `vue-router`, `pinia`.

## 🔐 Variáveis de ambiente
| Variável | Para quê |
|---|---|
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` | Web Push (em dev gera par efêmero se ausente) |
| `SECRET_KEY_BASE` | Segredo HS256 dos JWTs do paciente |
> **Asaas NÃO usa env var** — as credenciais vêm de `Financial::GatewaySetting` (no banco), por conta.
> `FRONTEND_URL` é histórico — o `apiBaseUrl` agora é sempre relativo (deixar vazio para funcionar em túneis/mobile).

## ☁️ Serviços externos
Asaas (PIX/boleto/cartão — webhook em `/webhooks/financial/asaas`, processado pelo plugin `financial`) · Web Push/VAPID · SMTP (OTP por email) · Telemed/LiveKit (indireto).

## ✅ Passo a passo
1. **Engine** carregado automaticamente — nada a registrar.
2. **Migrations**: `bin/rails db:migrate` (lista acima).
3. **Gems**: `bundle` (`jwt`, `web-push`).
4. **Web Push**: gerar par VAPID (`bin/rails runner 'puts WebPush.generate_key.to_h.to_json'`) e setar `VAPID_*`.
5. **Pagamentos**: cadastrar `Financial::GatewaySetting` da conta (api_key Asaas + environment) e configurar webhook no Asaas → `POST /webhooks/financial/asaas?account_id=:id` (sandbox primeiro).
6. **Build**: entrypoint `patient_portal` é auto-incluído; rodar `bin/vite dev` (dev) / `bin/vite build` (prod).
7. **Host/DNS**: `pacientes.klivy.app` (prod) ou `pacientes.lvh.me:3000` / `pacientes.localhost:3000` (dev) — o catch-all só ativa nesses hosts.
8. **OTP por email** (SMTP) configurado.
9. No dashboard: **Settings → Portal do Paciente**, aplicar um preset (`autonomy_guided` é o default).
10. Arquivos PWA (`public/patient_portal_sw.js`, `public/patient_portal_manifest.webmanifest`) já estão em `public/`.

---

# MÓDULO 3 — DOCUMENTOS (aba "Documentos")

**O que entrega:** a aba **Documentos** do dashboard, composta por **dois plugins acoplados**:
- **`document_templates`** — editor visual de templates (TipTap/ProseMirror) com **variáveis dinâmicas** (paciente/clínica/profissional/data), biblioteca global "Klivy" cloneável, pastas, e **geração de PDF via Grover** (HTML → Chromium headless).
- **`signatures`** — assinatura eletrônica via abstração de provider (**Mock** em dev, **Clicksign** em produção — hoje *skeleton*), com máquina de estados, webhook HMAC e job de download do PDF assinado.

Os dois se integram ao módulo de **pacientes**: templates alimentam "Gerar Documento"/"Consentimentos" e o `SendForSignatureModal` é embutido nas abas Documents/Consents do paciente.

## 📍 Localização
`plugins/document_templates/` e `plugins/signatures/`

## 🌳 Estrutura de pastas

### document_templates
**Backend**
- `plugins/document_templates/app/models/` — `document_template.rb`, `document_template_folder.rb`, `concerns/document_template_extension.rb` (concern injetado em `Document` e `ConsentRecord`: FK `document_template_id`, `rendered_html` imutável, `pdf_hash`).
- `plugins/document_templates/app/controllers/api/v1/accounts/` — `document_templates_controller.rb`, `document_template_folders_controller.rb`.
- `plugins/document_templates/app/services/document_templates/` — núcleo da geração: `pdf_generator.rb` (Resolver→Renderer→Grover→SHA256→attach), `renderer.rb` (ProseMirror→HTML com sanitizers), `resolver.rb`, `catalog.rb`, `variable.rb`, `formatters.rb`, `consent_record_builder.rb`.
- `plugins/document_templates/app/services/document_templates/readers/` — `patient_reader`, `clinic_reader`, `professional_reader`, `date_reader`.
- `plugins/document_templates/app/services/document_templates/variables/` — definições do catálogo por categoria (`patient_definitions`, `clinic_definitions`, `professional_definitions`, `date_definitions`).
- `plugins/document_templates/app/services/document_templates/seeds/` — `library_seeder.rb`, `builder.rb`, `clinical_templates.rb` (10 modelos), `consent_templates.rb` (15 modelos).
- `plugins/document_templates/app/serializers/`, `app/policies/`, `app/views/document_templates/` (`pdf_layout.html.erb`).
- `plugins/document_templates/lib/document_templates/` — `engine.rb` (injeta concern em Document/ConsentRecord + carrega rake tasks).
- `plugins/document_templates/lib/tasks/` — `document_templates.rake` (`seed_klivy_library`, `list_klivy`).
- `plugins/document_templates/config/` — `routes.rb`.

**Frontend**
- `plugins/document_templates/frontend/routes/documents/` — `DocumentsIndex.vue` (tela principal: tabs Meus/Klivy, grid/lista, pastas), `TemplateEditor.vue` (editor fullscreen com autosave) + `routes.js`.
- `plugins/document_templates/frontend/components/editor/` — `TipTapEditor.vue` (StarterKit + ~20 extensões), toolbar, `VariableNodeView.vue`, `VariablePickerMenu.vue`, `PaperContainer.vue`.
- `plugins/document_templates/frontend/components/editor/extensions/` — extensões TipTap custom: `VariableExtension.js`, `VariableSuggestionExtension.js`, `FontSize.js`, `LineHeight.js`, `Indent.js`, `PageBreak.js`.
- `plugins/document_templates/frontend/components/index/` — listagem (FolderSidebar, TemplateGrid/Card, TemplateList, KlivyLibrarySection…).
- `plugins/document_templates/frontend/components/modals/` e `components/shared/`.
- `plugins/document_templates/frontend/stores/` — `documentTemplates.js` (Pinia).
- `plugins/document_templates/frontend/api/`, `composables/`, `constants/`, `i18n/` (chave `DOCUMENT_TEMPLATES`), `styles/` (SCSS modular).

### signatures
**Backend**
- `plugins/signatures/app/models/` — `signature_request.rb` (polimórfico `signable` = Document/ConsentRecord, máquina de estados, `audit_log` JSONB).
- `plugins/signatures/app/controllers/api/v1/accounts/` — `signature_requests_controller.rb`.
- `plugins/signatures/app/controllers/webhooks/` — `clicksign_controller.rb` (webhook público, HMAC).
- `plugins/signatures/app/services/signatures/` — `provider.rb` (interface), `provider_resolver.rb`, `request_creator.rb`.
- `plugins/signatures/app/services/signatures/providers/` — `mock_provider.rb` (dev), `clicksign_provider.rb` (**skeleton**, métodos ainda `NotImplementedError`).
- `plugins/signatures/app/jobs/signatures/` — `download_signed_pdf_job.rb`.
- `plugins/signatures/app/serializers/`, `app/policies/`, `lib/signatures/engine.rb` (injeta `has_many :signature_requests` em Document/ConsentRecord/Account), `config/routes.rb`.

**Frontend**
- `plugins/signatures/frontend/components/` — `SendForSignatureModal.vue`, `SignatureStatusCard.vue`.
- `plugins/signatures/frontend/api/`, `composables/`, `constants/`, `i18n/` (chave `SIGNATURES`), `styles/`.

## 🔑 Arquivos-chave
- `plugins/document_templates/app/models/document_template.rb` — tipos clínicos/consentimento, sources `klivy/clinic/cloned`, valida `content_json` ProseMirror.
- `plugins/document_templates/app/models/concerns/document_template_extension.rb` — concern injetado em Document/ConsentRecord.
- `plugins/document_templates/app/services/document_templates/pdf_generator.rb` — orquestra a geração de PDF (`GROVER_TIMEOUT_MS`).
- `plugins/document_templates/app/services/document_templates/seeds/library_seeder.rb` — seed idempotente da biblioteca Klivy.
- `plugins/document_templates/frontend/components/editor/TipTapEditor.vue` — editor; emite JSON ProseMirror consumido pelo Renderer Ruby.
- `plugins/document_templates/frontend/components/editor/extensions/VariableExtension.js` — node de variável (chip).
- `plugins/signatures/app/models/signature_request.rb` — estados `pending→sent→viewed→signed→completed | cancelled/failed/expired`.
- `plugins/signatures/app/services/signatures/request_creator.rb` — extrai PDF do signable → cria request → `provider.create_envelope`.
- `plugins/signatures/app/services/signatures/providers/clicksign_provider.rb` — **implementar para produção** (hoje skeleton).
- `plugins/signatures/app/controllers/webhooks/clicksign_controller.rb` — webhook HMAC → transições + `DownloadSignedPdfJob`.
- `plugins/signatures/frontend/components/SendForSignatureModal.vue` — modal embutido nas abas do paciente.

## 🗄️ Migrations (em `db/migrate/` da raiz — 5)
```
20260527000001_create_document_template_folders.rb
20260527000002_create_document_templates.rb
20260527000003_add_template_ref_to_documents.rb
20260527000004_add_template_ref_to_consent_records.rb
20260527000005_create_signature_requests.rb
```

## 🛣️ Rotas
- **document_templates:** `/api/v1/accounts/:account_id/document_templates` (collection `variables`, `klivy_library`; member `duplicate`, `clone_to_account`, `archive`, `unarchive`) e `/document_template_folders`.
- **signatures:** `/api/v1/accounts/:account_id/signature_requests` (member `cancel`, `resend`, `refresh_status`) + webhook público `POST /webhooks/clicksign`.
- **Frontend (dashboard):** `/app/accounts/:accountId/documents` (lista) e `/app/accounts/:accountId/documents/:id/edit` (editor).
- `signatures` **não tem rota de página** — seus componentes são embutidos nas abas do paciente.

## 🔌 Wiring de frontend
- `dashboard.routes.js`: `import { routes as documentTemplateRoutes } from '@plugins/document_templates/frontend/routes/routes'` + `...documentTemplateRoutes`.
- `Sidebar.vue`: item **'Documents'** (`i-lucide-file-text`, label `t('SIDEBAR.DOCUMENTS','Documentos')`, `to: accountScopedRoute('documents_dashboard_index')`, depois de Patients); RBAC **Documents → módulo `patients`**.
- `i18n/locale/{en,pt_BR}/index.js`: importar `@plugins/document_templates/frontend/i18n` e `@plugins/signatures/frontend/i18n`.
- `signatures`: o `SendForSignatureModal` é importado direto em `plugins/patients/frontend/routes/patients/tabs/DocumentsTab.vue` e `ConsentsTab.vue` (não registra rota nem sidebar).

## 🧩 Depende dos plugins
`patients` (dono de Document/ConsentRecord; reusa `Patients::PdfGenerator`/`PatientReader`), `beclinic_core`. (`signatures` depende também de `document_templates`.)

## 📦 Dependências
- **Gems:** `grover (~> 1.2)` (requer **Chromium/Puppeteer** no servidor).
- **npm:** família TipTap — `@tiptap/core`, `@tiptap/vue-3`, `@tiptap/starter-kit`, `@tiptap/suggestion` + extensões (`underline`, `text-align`, `text-style`, `color`, `font-family`, `link`, `table`, `table-row/cell/header`, `placeholder`, `character-count`, `highlight`, `subscript`, `superscript`, `image`).

## 🔐 Variáveis de ambiente
| Variável | Para quê |
|---|---|
| `GROVER_TIMEOUT_MS` | Timeout do Chromium na geração de PDF (default 30000) |
| `SIGNATURES_PROVIDER` | `mock` (dev/test) ou `clicksign` (produção) |
| `CLICKSIGN_API_TOKEN` | Token da API Clicksign v3 (obrigatório p/ o provider) |
| `CLICKSIGN_BASE_URL` | Base da API (default `https://app.clicksign.com`; sandbox `https://sandbox.clicksign.com`) |
| `CLICKSIGN_WEBHOOK_SECRET` | Segredo HMAC do webhook (se vazio, aceita tudo — inseguro) |
| `VERBOSE_SEEDS` | Logs ao rodar o seed da biblioteca Klivy |

## ☁️ Serviços externos
Grover + Chromium/Puppeteer (HTML→PDF, **requerido no servidor**) · Clicksign API v3 (produção, integração ainda skeleton) · ActionCable (broadcast de assinatura concluída) · Active Storage (anexo dos PDFs).

## ✅ Passo a passo
1. **Engines** carregados automaticamente — nada a registrar.
2. **Migrations** (5 acima): `bin/rails db:migrate`.
3. **Biblioteca Klivy**: `bundle exec rake document_templates:seed_klivy_library` (conferir com `rake document_templates:list_klivy`).
4. **Chromium/Puppeteer** instalado no servidor (Dockerfile) para o Grover; ajustar `GROVER_TIMEOUT_MS` se preciso.
5. **Frontend**: editar `dashboard.routes.js`, `Sidebar.vue` (item + RBAC `patients`) e `i18n/locale/{en,pt_BR}/index.js`; instalar deps `@tiptap/*`; buildar via Vite.
6. **Assinaturas**: em dev/test funciona out-of-the-box com **MockProvider**. Para produção: `SIGNATURES_PROVIDER=clicksign` + as `CLICKSIGN_*`, configurar webhook → `POST /webhooks/clicksign`, e **implementar os métodos do `clicksign_provider.rb`** (hoje `NotImplementedError`).
7. **Integração com pacientes** (já feita): `document_template_id` no create de documents/consents roteia para o Grover; `SendForSignatureModal` já embutido nas abas do paciente.

---

# CHECKLIST FINAL DE REPLICAÇÃO (ordem recomendada)

1. **Instalar as bases primeiro** (nesta ordem): `beclinic_core` → `patients` → `agenda` → `financial`. Sem elas, os três módulos não sobem.
2. **Copiar as pastas dos plugins** desejados: `plugins/telemed/`, `plugins/patient_portal/`, `plugins/document_templates/`, `plugins/signatures/`.
3. **Backend (gems)**: adicionar ao Gemfile e `bundle install` — `livekit-server-sdk`, `ruby_llm`, `ruby_llm-schema`, `ruby-openai`, `aws-sdk-s3`, `jwt`, `web-push`, `grover`, `prawn`/`prawn-table`, `down`, `image_processing`, `pundit`, `sidekiq`/`sidekiq-cron`.
4. **Frontend (npm)**: instalar `livekit-client`, `@livekit/track-processors`, família `@tiptap/*`, `vue/vue-router/pinia` (já presentes), `dompurify`/`vue-dompurify-html`.
5. **Vite**: garantir alias `@plugins → ./plugins` em `vite.config.ts` e `watchAdditionalPaths: ["plugins/**/*"]` em `config/vite.json`.
6. **Wiring manual do frontend (dashboard)** — editar:
   - `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` (imports + spread das rotas)
   - `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (itens Teleconsulta/Documents + `SIDEBAR_NAME_TO_MODULE`)
   - `app/javascript/dashboard/i18n/locale/{en,pt_BR}/index.js` (i18n dos plugins)
   - `app/javascript/dashboard/store/index.js` (módulos Vuex, ex.: `beclinicPermissions`)
   - `app/javascript/dashboard/helper/routeHelpers.js` (regras RBAC — **não esquecer**)
7. **Entrypoint do portal**: garantir `app/javascript/entrypoints/patient_portal.js`.
8. **Montar as engines no host** (`config/routes.rb`): `mount Telemed::Engine` / `PatientPortal::Engine` / `DocumentTemplates::Engine` / `Signatures::Engine`, todos `at: '/'`.
9. **Migrations**: copiar todas as migrations citadas para `db/migrate/` da raiz e `bin/rails db:migrate`.
10. **ENV**: configurar todas as variáveis das 3 tabelas acima.
11. **Infra**: LiveKit + Egress + Redis (telemed), Chromium/Puppeteer + ffmpeg (documentos/telemed), SMTP (OTP), DNS `pacientes.*` (portal).
12. **Seeds/config por conta**: rodar `document_templates:seed_klivy_library`; ativar gravação telemed na conta; aplicar preset do portal.

> **Pegadinhas que mais quebram replicação:**
> - Migrations ficam na **raiz** `db/migrate/`, **não** dentro do plugin (os `plugins/*/db/migrate/` estão vazios).
> - Frontend **não** tem auto-discovery: se não editar os 5 arquivos do core, a aba não aparece (e se esquecer o `routeHelpers.js`, a rota fica acessível por URL sem permissão).
> - Rotas se montam no **host** (`config/routes.rb`), além do `routes.rb` do plugin.
> - O Portal do Paciente é um **SPA separado** (Pinia), não faz parte do bundle/sidebar do dashboard.
