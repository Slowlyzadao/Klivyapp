# 04 — Backend (Rails)

## 4.1 Mapa de componentes

```
plugins/telemed/app/
├── controllers/
│   ├── api/v1/accounts/telemed/
│   │   ├── sessions_controller.rb            # JWT + waiting room (clínica)
│   │   ├── teleconsultas_controller.rb       # listagem + detalhe
│   │   └── proposed_evolutions_controller.rb # update/approve/reject
│   ├── api/v1/patient_portal/telemed/
│   │   └── sessions_controller.rb            # JWT pra paciente
│   └── webhooks/livekit/
│       └── egress_controller.rb              # callback gravação
├── services/telemed/
│   ├── session_issuer.rb               # JWT LiveKit
│   ├── recording_orchestrator.rb       # start/stop 3 egress
│   ├── recording_storage.rb            # R2 client
│   ├── transcription_provider.rb       # factory Whisper / gpt-4o
│   ├── evolution_provider.rb           # factory Claude / OpenAI
│   ├── evolution_provider/claude.rb    # implementação Claude
│   ├── proposed_evolution_approval_service.rb  # approve → SessionLog
│   ├── session.rb                      # estado da sala (janela, bloqueios)
│   ├── session_event_handler.rb        # joined/left
│   ├── session_tracker.rb              # custom_attributes parser
│   ├── admission_window.rb             # filtra admissões válidas
│   ├── status_transition.rb            # AgendaEvent state machine
│   ├── room_code.rb                    # slug `klivy-acc<id>-ev<id>`
│   └── credentials_resolver.rb         # ENV / installation_config
└── jobs/telemed/
    ├── transcribe_recording_job.rb       # OpenAI → segments
    ├── generate_evolution_job.rb         # Claude → procedure_fields
    ├── mark_no_show_job.rb               # 5min sem paciente
    ├── mark_in_progress_job.rb           # 5min ambos presentes
    └── enforce_recording_quota_job.rb    # housekeeping
```

---

## 4.2 Controllers

### 4.2.1 `Api::V1::Accounts::Telemed::SessionsController`

`plugins/telemed/app/controllers/api/v1/accounts/telemed/sessions_controller.rb`

Endpoints (dentista na sala):

| Método | Path | Ação |
|--------|------|------|
| POST | `:event_id/telemedicine_token` | Emite JWT (chama `SessionIssuer`). Retorna `{ url, token, room_code, dev_mode, outside_window, requires_admit }`. |
| POST | `:event_id/telemedicine_event` | Reporta `kind=joined/left` → automação de status (arrived → in_progress) via `SessionEventHandler`. |
| POST | `:event_id/telemedicine/admit_patient` | Chama `UpdateParticipant` no LiveKit liberando `canPublish=true` pra identity `patient-<id>`. |
| POST | `:event_id/telemedicine/start_recording` | `RecordingOrchestrator.start!(event, force: true)`. |
| POST | `:event_id/telemedicine/stop_recording` | `RecordingOrchestrator.stop!(recording)`. |
| POST | `:event_id/telemedicine/confirm_completed` | Marca AgendaEvent como `completed` pós-encerramento (modal "Conseguiu atender?"). |

Autorização: `AgendaEventPolicy#telemedicine_join?` — dono do evento OU admin.

### 4.2.2 `Api::V1::Accounts::Telemed::TeleconsultasController`

`plugins/telemed/app/controllers/api/v1/accounts/telemed/teleconsultas_controller.rb`

| Método | Path | Ação |
|--------|------|------|
| GET | `/teleconsultas` | Lista paginada (`tab=upcoming/in_progress/finished/no_show`, `professional_id`, `date_from/to`). |
| GET | `/teleconsultas/counts` | Contagem por aba (badges). |
| GET | `/teleconsultas/:id` | Detalhe completo (paciente, recording, transcript, evolution). |
| GET | `/teleconsultas/:id/recording_url?kind=composite_audio` | Signed URL R2 (TTL 5min). |
| POST | `/teleconsultas/:id/retranscribe` | Admin-only: re-enfileira `TranscribeRecordingJob`. |
| POST | `/teleconsultas/:id/reevolve` | Admin-only: re-enfileira `GenerateEvolutionJob`. |

Pontos importantes:
- `recording_url` valida `recording.archived?` — bloqueia URL pra gravações arquivadas.
- `serialize_detail` guarda `transcript_text` atrás de `transcript_ready` flag (evita 500 se `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` faltar em dev).
- Paginação tem clamp em `per_page` (max 100) pra evitar DoS.
- `index` usa `includes(:user, :agenda_service, contact: :patient, telemed_recordings: :proposed_evolutions)` (N+1 prevention).

### 4.2.3 `Api::V1::Accounts::Telemed::ProposedEvolutionsController`

`plugins/telemed/app/controllers/api/v1/accounts/telemed/proposed_evolutions_controller.rb`

| Método | Path | Ação |
|--------|------|------|
| PATCH | `/proposed_evolutions/:id` | Edita `soap_structure`, `raw_markdown`, `procedure_fields`. Marca como `edited` se vinha de `pending_review`. |
| POST | `/proposed_evolutions/:id/approve` | Cria `SessionLog` (via `ProposedEvolutionApprovalService`), marca evolution → `approved`. |
| POST | `/proposed_evolutions/:id/reject` | Marca → `rejected` com `reviewer_notes` (justificativa obrigatória). |

Whitelists explícitas:

```ruby
SOAP_PERMITTED_KEYS = %i[subjetivo objetivo avaliacao plano].freeze

PROCEDURE_PERMITTED_KEYS = %i[
  queixa_do_dia avaliacao_clinica procedimento_realizado area_tratada
  produto_utilizado quantidade_dose unidade lote validade
  intercorrencias resultado_imediato detalhes_proxima_consulta
  retorno_em_dias observacao
].freeze
```

### 4.2.4 `Webhooks::Livekit::EgressController`

`plugins/telemed/app/controllers/webhooks/livekit/egress_controller.rb`

POST `/webhooks/livekit/egress`. **Sem autenticação Devise** — autentica via JWT no header `Authorization: <token>`:

```ruby
decoded = JWT.decode(
  token, secret, true,
  algorithm: 'HS256',
  verify_iat: true,
  verify_expiration: true,
  leeway: 30   # 30s pra clock skew entre LiveKit e Rails
)
```

Adicionalmente valida SHA-256 do body bruto contra `decoded['sha256']` (LiveKit assina o body).

Eventos processados:

| LiveKit event | Ação |
|---------------|------|
| `egress_started` | `recording.update!(status: 'recording')` |
| `egress_ended` (status SUCCESS) | Persiste `*_audio_key`, marca role concluído. Se TODOS concluídos → `transcribe_recording_job` |
| `egress_ended` (status FAILED/ABORTED) | Marca role como falhado. Se todos falham → `recording.fail!` |
| `track_published` | Persiste `track_sid` em `custom_attributes['telemed_session']['published_tracks']` |

Idempotência: `find_or_create_by(egress_id:)` + `recording.with_lock` (webhook chega 2-3x).

---

## 4.3 Services

### 4.3.1 `Telemed::SessionIssuer`

`plugins/telemed/app/services/telemed/session_issuer.rb`

Emite JWT LiveKit (TTL 2h) com claims:

```json
{
  "iss": "<api_key>",
  "sub": "doctor-73",
  "iat": ...,
  "exp": ...,
  "video": {
    "room": "klivy-acc1-ev86",
    "roomJoin": true,
    "canPublish": true,    // false pro paciente até admit
    "canSubscribe": true,
    "canPublishData": true
  }
}
```

Identity prefixada `doctor-<user_id>` / `patient-<patient_id>` permite o LiveKit (e o frontend) distinguirem roles sem confiar em metadata custom.

### 4.3.2 `Telemed::RecordingOrchestrator`

`plugins/telemed/app/services/telemed/recording_orchestrator.rb`

`start!(event, force:)`:
1. Cria `TelemedRecording(status: 'pending')`.
2. Chama `LiveKit::EgressService`:
   - `start_room_composite_egress` (composite OGG)
   - `start_participant_egress` × 2 (doctor + patient isolated)
3. Persiste os 3 `egress_id`s na recording.

Retry pra `list_participants` (10×, 8s): LiveKit demora a propagar a presença do participante; sem retry a chamada pode pegar room vazia e abortar gravação.

Encoding fixo:
```ruby
audio: { codec: 'opus', bitrate: 64_000, channels: 1 }
```

OGG mono opus 64kbps → ~28 MB por hora. Suficiente pra transcrição (Whisper/gpt-4o aceitam até 25MB por arquivo).

### 4.3.3 `Telemed::RecordingStorage`

`plugins/telemed/app/services/telemed/recording_storage.rb`

Cliente `Aws::S3::Client` apontando pra R2:

```ruby
Aws::S3::Client.new(
  region: ENV['TELEMED_STORAGE_REGION'] || 'auto',
  endpoint: ENV['TELEMED_STORAGE_ENDPOINT'],
  access_key_id: ENV['TELEMED_STORAGE_ACCESS_KEY_ID'],
  secret_access_key: ENV['TELEMED_STORAGE_SECRET_ACCESS_KEY'],
  force_path_style: true   # R2 não suporta virtual-hosted style
)
```

Métodos:
- `download(key, path)` — baixa pra tmpfile (usado por `TranscribeRecordingJob`).
- `signed_url(key, ttl: 5.min)` — URL pública temporária (player).
- `delete(key)` — usado pra deletar doctor/patient audio após transcrição.

### 4.3.4 `Telemed::EvolutionProvider`

`plugins/telemed/app/services/telemed/evolution_provider.rb`

Factory provider-agnostic:

```ruby
Telemed::EvolutionProvider.for('claude-sonnet-4.6')
# → Telemed::EvolutionProvider::Claude.new(model: 'claude-sonnet-4-6')
```

Result struct (passada do provider pro caller):

```ruby
Result = Struct.new(
  :soap_structure,    # { subjetivo, objetivo, avaliacao, plano }
  :raw_markdown,      # texto bruto retornado pelo modelo
  :attention_points,  # array de hashes
  :summary,           # markdown "Resumo Executivo"
  :procedure_fields,  # 14 chaves
  :provider,          # 'claude/claude-sonnet-4-6'
  :input_tokens,
  :output_tokens,
  keyword_init: true
)
```

#### `Telemed::EvolutionProvider::Claude` (detalhe)

`plugins/telemed/app/services/telemed/evolution_provider/claude.rb`

Chamada via `ruby_llm`:

```ruby
chat = context.chat(
  model: 'claude-sonnet-4-6',
  assume_model_exists: true,   # ruby_llm registry estático não conhece 4-6 ainda
  provider: :anthropic
).with_instructions(SYSTEM_PROMPT)

response = chat.ask(user_content)
```

Por que `assume_model_exists: true`: o `ruby_llm` carrega registry estático no boot. Quando a Anthropic libera modelo novo (`claude-sonnet-4-6`, `claude-opus-4-7`), `context.chat(model:)` levanta `ModelNotFoundError` antes mesmo de chamar a API. O flag bypassa essa checagem; a API real valida o nome.

Sistema prompt + parser: detalhado em [08-prompts-ia.md](08-prompts-ia.md).

### 4.3.5 `Telemed::ProposedEvolutionApprovalService`

`plugins/telemed/app/services/telemed/proposed_evolution_approval_service.rb`

Ponto crítico: cruza fronteira "IA → prontuário oficial".

```ruby
def call
  raise 'Proposta já aprovada' if @evolution.status == 'approved'
  raise 'Proposta rejeitada não pode ser aprovada' if @evolution.status == 'rejected'

  ActiveRecord::Base.transaction do
    session_log = build_session_log     # mapeia procedure_fields → SessionLog
    session_log.save!

    @evolution.update!(
      status: 'approved',
      reviewed_by: @actor,
      reviewed_at: Time.current
    )

    session_log.update_column(:proposed_evolution_id, @evolution.id)
    Result.new(evolution: @evolution.reload, session_log: session_log, clinical_note: session_log)
  end
end
```

Mapeamento `procedure_fields` → `SessionLog`:

| `procedure_fields` key | `SessionLog` column / jsonb |
|------------------------|------------------------------|
| `queixa_do_dia` | `complaint_of_day` |
| `avaliacao_clinica` | `assessment` |
| `procedimento_realizado` | `procedure_name` (default `"Teleconsulta"` se vazio) |
| `area_tratada` | `areas_treated[0].region` (jsonb array) |
| `produto_utilizado` | `products_used[0].name` (jsonb array) |
| `quantidade_dose` | `products_used[0].quantity` |
| `unidade` | `products_used[0].unit` |
| `lote` | `products_used[0].batch` |
| `validade` | `products_used[0].expires_at` |
| `intercorrencias` | `complications` |
| `resultado_imediato` | `result_observed` |
| `detalhes_proxima_consulta` | `next_consultation_details` |
| `retorno_em_dias` | `return_in_days` + `return_needed: true` se != nil |
| `observacao` | `observation` |

Demais campos do `SessionLog`:
- `account_id`, `patient_id` — derivados do `agenda_event`
- `professional_id` — `event.user_id || actor.id`
- `appointment_id` — `event.id`
- `performed_at` — `event.starts_at || Time.current`
- `duration_minutes` — calculado de `(ends_at - starts_at) / 60` (AgendaEvent não tem coluna)
- `status` — `'draft'` (dentista pode assinar depois via UI da aba Evolução do paciente)

### 4.3.6 `Telemed::Session`

`plugins/telemed/app/services/telemed/session.rb`

Resolve estado da sala antes de emitir token:

```ruby
Telemed::Session.new(event: event, actor: user).call
# → Result.new(
#     enabled: true,
#     can_join_now: false,
#     outside_window: true,
#     window_closed: false,
#     too_early: true,
#     starts_in_seconds: 600,
#     permanently_blocked: false,
#     block_reason: nil
#   )
```

PERMANENT_REASONS (bloqueia entrada para sempre):
- evento cancelado / `status` final (`completed`, `no_show`)
- telemedicina desativada na conta

WINDOW_REASONS (só fora da janela; entra "sala de espera" no Patient Portal):
- `too_early` (consulta começa em > 15 min)
- `window_closed` (consulta acabou há > 30 min)

### 4.3.7 `Telemed::SessionEventHandler`

`plugins/telemed/app/services/telemed/session_event_handler.rb`

Processa eventos `joined`/`left` do frontend:

- `joined` do doutor: registra `doctor_joined_at` em `event.custom_attributes['telemed_session']`. Marca `event.status: 'arrived'` se ainda `confirmed/scheduled`. Enfileira `MarkNoShowJob` (5min) caso paciente não chegue.

- `joined` do paciente: registra `patient_joined_at`. Se ambos presentes, enfileira `MarkInProgressJob` (5min). Cancela `MarkNoShowJob` se enqueued.

- `left`: registra timestamp. **Não marca completed automaticamente** (audit 2026-05-21 — se conexão cair, sessão era marcada erradamente).

A única forma de marcar `completed` agora: dentista clica "Sim, consegui atender" no modal pós-encerramento (`POST /confirm_completed`).

---

## 4.4 Jobs (Sidekiq)

### 4.4.1 `Telemed::TranscribeRecordingJob`

`plugins/telemed/app/jobs/telemed/transcribe_recording_job.rb`

Queue: `:low`. Trigger: webhook `egress_ended` quando todos os 3 egress concluíram.

Fluxo:
1. Marca `recording.status = 'transcribing'`.
2. Baixa do R2: `doctor_audio_key`, `patient_audio_key` (paralelo, tmpfiles).
3. Chama `Telemed::TranscriptionProvider.for(...).call(audio_paths)`.
4. Persiste `transcript_text` (encrypted) e `transcript_segments` (jsonb).
5. Deleta do R2: `doctor_audio_key`, `patient_audio_key` (privacy + cost). Composite preservado pro player.
6. Marca `recording.status = 'transcribed'`.
7. Enfileira `GenerateEvolutionJob`.

Retry: 3× exponencial. `discard_on Telemed::PermanentFailure` (arquivo > 25MB).

### 4.4.2 `Telemed::GenerateEvolutionJob`

`plugins/telemed/app/jobs/telemed/generate_evolution_job.rb`

Queue: `:low`. Trigger: pós-`TranscribeRecordingJob`.

Fluxo:
1. Marca `recording.status = 'evolving'`.
2. `resolve_provider_name(account)`: lê de `account.patient_portal_setting.telemedicine_recording['ai_provider']` ou `EvolutionProvider::DEFAULT_PROVIDER` (`claude-sonnet-4.6`).
3. `build_patient_context(event)`: alergias, medicações, 3 últimas notas clínicas.
4. `EvolutionProvider.for(provider_name).call(transcript:, patient_context:)`.
5. Cria `ProposedEvolution(status: 'pending_review', procedure_fields: result.procedure_fields, ...)`.
6. Marca `recording.status = 'ready'`.
7. Enfileira `EnforceRecordingQuotaJob`.
8. `notify_dentist(recording)` — cria `PatientPortalNotification` in-app.

Tratamento de retry duplicado: `rescue ActiveRecord::RecordNotUnique` (partial unique index em `pending_review`). Atualiza a existente em vez de criar duplicata.

### 4.4.3 `Telemed::MarkNoShowJob`

`plugins/telemed/app/jobs/telemed/mark_no_show_job.rb`

Queue: `:high`. Delay: 5 min após doctor entrar sem paciente.

Validação dupla (idempotente):
- Recarrega evento.
- Se `doctor_joined_at` mudou desde o agendamento do job → ignora (nova sessão).
- Se paciente já chegou → ignora.
- Senão → `event.update!(status: 'no_show')`.

### 4.4.4 `Telemed::MarkInProgressJob`

Mesma estrutura do `MarkNoShowJob`. Delay: 5 min após `both_started_at`.

### 4.4.5 `Telemed::EnforceRecordingQuotaJob`

Queue: `:purgable`. Trigger: pós-`GenerateEvolutionJob`.

```ruby
quota = account.patient_portal_setting.telemedicine_recording['max_active_recordings'] || 15
active = account.telemed_recordings.where(archived_at: nil).order(created_at: :desc)
return if active.count <= quota

active.offset(quota).each(&:archive!)  # deleta do R2, mantém DB
```

Importante: SessionLog (prontuário) permanece — só a gravação é arquivada (R2 keys removidas).

---

## 4.5 Engine + Routes

### `plugins/telemed/lib/telemed/engine.rb`

```ruby
module Telemed
  class Engine < ::Rails::Engine
    config.to_prepare do
      Account.class_eval do
        has_many :telemed_recordings, dependent: :destroy
        has_many :telemed_consents,   dependent: :destroy
      end
      Patient.class_eval do
        has_many :telemed_consents, dependent: :nullify
      end
      AgendaEvent.class_eval do
        has_many :telemed_recordings, dependent: :destroy
      end
    end
  end
end
```

### `plugins/telemed/config/routes.rb`

```ruby
Rails.application.routes.draw do
  scope path: 'webhooks/livekit' do
    post '/egress', to: 'webhooks/livekit/egress#create'
  end

  namespace :api do
    namespace :v1 do
      namespace :accounts do
        namespace :telemed do
          resources :teleconsultas, only: [:index, :show] do
            collection { get :counts }
            member do
              get  :recording_url
              post :retranscribe
              post :reevolve
            end
          end
          resources :proposed_evolutions, only: [:update] do
            member do
              post :approve
              post :reject
            end
          end
        end

        # Endpoints "session" montados em agenda_events nested (legacy compat).
        # Caminho real: /agenda_events/:id/telemedicine_*
      end

      namespace :patient_portal do
        namespace :telemed do
          resources :sessions, only: [:create] do
            collection { post :event }
          end
        end
      end
    end
  end
end
```

---

## 4.6 Policies (Pundit)

`plugins/telemed/app/policies/proposed_evolution_policy.rb`:

```ruby
class ProposedEvolutionPolicy < ApplicationPolicy
  def show?
    owner_or_admin?
  end

  def update?
    owner_or_admin? && record.status != 'approved'
  end

  def approve?
    user.permissions.include?('create_clinical_note') && owner_or_admin?
  end

  def reject?
    approve?
  end

  private

  def owner_or_admin?
    return true if admin_with_all_scope?
    record.telemed_recording.agenda_event.user_id == user.id
  end
end
```

---

## 4.7 Boot guards e configs

`config/initializers/telemed.rb`:

```ruby
# Fail-fast em prod sem encryption key
if Rails.env.production? && ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].blank?
  raise 'Telemed: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ausente em prod (LGPD violation).'
end

# Warn se LiveKit não configurado
if ENV['LIVEKIT_API_KEY'].blank? && Rails.env.production?
  Rails.logger.warn '[Telemed] LIVEKIT_API_KEY ausente — sala não vai funcionar.'
end
```
