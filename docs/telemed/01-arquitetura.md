# 01 — Arquitetura

## 1.1 Visão macro

O plugin **Telemed** é um **Rails Engine** (`plugins/telemed/lib/telemed/engine.rb`) que se acopla ao core Klivy via injeção de associações em modelos existentes — sem monkey-patch invasivo. O frontend é um conjunto de componentes Vue 3 isolados em `plugins/telemed/frontend/`, montados pelo dashboard core via rotas registradas.

**Princípio de design**: a teleconsulta não substitui o prontuário existente — *alimenta* ele. A IA gera proposta (`ProposedEvolution`), o dentista revisa/edita/assina, e a aprovação cria um `SessionLog` (modelo de prontuário unificado do sistema). Em nenhum momento a IA grava direto no prontuário sem aprovação humana — barreira de responsabilidade clínica + LGPD + CFM.

---

## 1.2 Estrutura de pastas

```
plugins/telemed/
├── lib/telemed/
│   ├── engine.rb              # Rails::Engine — registro do plugin
│   └── version.rb
├── config/
│   └── routes.rb              # rotas montadas em /api/v1 e /webhooks
├── app/
│   ├── controllers/api/v1/accounts/telemed/   # endpoints autenticados (clínica)
│   ├── controllers/api/v1/patient_portal/telemed/  # endpoints paciente
│   ├── controllers/webhooks/livekit/          # webhook egress
│   ├── models/                                # TelemedRecording, ProposedEvolution, TelemedConsent
│   ├── services/telemed/                      # ~12 services (orquestração, IA, transcrição)
│   ├── jobs/telemed/                          # 5 jobs Sidekiq
│   └── policies/                              # Pundit
├── frontend/
│   ├── dashboard/                             # visão clínica
│   ├── patient/                               # visão paciente
│   ├── shared/components/TelemedicineRoom.vue # sala LiveKit (puro)
│   └── styles/                                # SCSS isolado
└── db/migrate/                                # migrations específicas
```

---

## 1.3 Camadas (request lifecycle)

### Sala de vídeo

```
Browser (Vue + livekit-client) ──WS──► LiveKit Server (self-host / Cloud)
                                            │
Browser ──HTTP──► Rails (SessionsController)│
   ↑ JWT token        │                     │
   └── SessionIssuer ─┘ assina JWT          │
                                            │
                                  Egress ───┴──► Cloudflare R2 (3 arquivos opus)
                                            │
                                  Webhook ──┴──► Rails (EgressController)
                                                      │
                                                      ▼
                                            TranscribeRecordingJob (Sidekiq)
                                                      │
                                                      ▼
                                            GenerateEvolutionJob (Sidekiq)
                                                      │
                                                      ▼
                                            UI atualiza via ActionCable
```

### Decisão arquitetural chave: **separação clara entre 3 contextos**

1. **Sala em tempo real** (sync): LiveKit + browser. Rails só emite token e recebe relatórios `joined`/`left`. NÃO há código de Rails no caminho crítico da chamada — se Rails cair, a sala continua funcionando.

2. **Pós-chamada** (async, Sidekiq): transcrição + IA + persistência. Tudo encadeado por jobs. Falhas são isoladas (transcript falha não impede a evolução de ser gerada manualmente; evolução falha não destrói o transcript).

3. **Aprovação humana** (sync, dashboard): dentista revisa, edita os 14 campos do `procedure_fields`, marca checkbox de responsabilidade, clica "Salvar e Assinar". Só aí o `SessionLog` é criado.

---

## 1.4 Decisões arquiteturais explícitas

### 1.4.1 Audio-only por padrão (não vídeo)

O backend grava **apenas áudio** (Egress configurado pra `OGG mono opus 64kbps`, ~28 MB/h). Vídeo flui em tempo real entre browsers, mas não é persistido.

**Por quê**: privacidade (HIPAA/LGPD — vídeo de paciente em situação clínica é dado ultrasensível), custo de storage (~10x mais), valor clínico (transcrição cobre 95% do uso documental).

Se for replicar com vídeo, basta trocar tipo de Egress no `RecordingOrchestrator`.

### 1.4.2 3 arquivos de áudio por consulta (não 1)

A gravação usa **3 jobs Egress paralelos**:
- `ParticipantEgress` do dentista → `doctor_audio_key`
- `ParticipantEgress` do paciente → `patient_audio_key`
- `RoomCompositeEgress` → `composite_audio_key`

**Por quê**: a diarização (saber quem falou) fica perfeita com áudios isolados — sem precisar de voiceprint. O composite é o que toca no player do dashboard (mais natural pro humano ouvir). Os dois individuais são deletados após a transcrição (privacidade + custo).

### 1.4.3 Waiting room server-side

O LiveKit token do paciente é emitido com `canPublish: false`. O dentista chama um endpoint (`POST /admit_patient`) que dispara `UpdateParticipant` no LiveKit liberando a publicação. Sem isso, paciente entra mas fica "mudo" — câmera/mic dele não publicam até o dentista deixar.

**Por quê**: evita constrangimento clínico (paciente entrar antes da hora e ver outra consulta em andamento; dentista no banheiro etc.).

### 1.4.4 Anti-stale sequencer no fetchDetail

A página de detalhe da teleconsulta pode receber 2+ fetches concorrentes (ActionCable dispara fetch quando status muda; usuário também pode forçar refresh). Sem proteção, requests respondem fora de ordem e sobrescrevem state mais recente com state antigo.

Implementação: contador `fetchSeq` incrementado a cada chamada; só aplica resultado se a geração continua sendo a mais recente quando a Promise resolve. Veja `TeleconsultaDetailPage.vue`.

### 1.4.5 Aprovação cria `SessionLog`, não `ClinicalNote`

Decisão tardia (audit 2026-05-26): o plugin originalmente criava `ClinicalNote` (modelo legado), mas o resto do app já usa `SessionLog` (modelo unificado novo, com `migrated_from_clinical_note_id`). Resultado: evoluções aprovadas existiam no banco mas não apareciam nas abas do paciente.

Correção: `ProposedEvolutionApprovalService` agora mapeia `procedure_fields` (14 campos) → colunas/jsonb do `SessionLog`. Veja [04-backend.md](04-backend.md#proposedeevolutionapprovalservice).

### 1.4.6 Encryption seletiva (LGPD)

`encrypts :transcript_text` em `TelemedRecording`; `encrypts :raw_markdown, :reviewer_notes, :summary` em `ProposedEvolution`. Configurado com `support_unencrypted_data: true` pra permitir migração suave (lê plaintext antigo, grava encrypted novo).

ENV `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` obrigatório em prod (boot guard em `config/initializers/telemed.rb` faz fail-fast se faltar).

### 1.4.7 IA: Claude Sonnet 4.6 como default

Razões: WER baixo em PT-BR, segue formato estruturado consistentemente, contexto de 200k tokens (cobre teleconsultas de até ~50 min sem chunking). Custo ~$0.06/consulta (audit 2026-05-22).

Provider é trocável via setting `account.patient_portal_setting.telemedicine_recording['ai_provider']`. Default no código `claude-sonnet-4.6`. Fluxo: `Telemed::EvolutionProvider.for(model_id)` → factory que retorna Claude ou OpenAI provider.

---

## 1.5 Pontos de extensão no core (mínimos)

O engine **não monkeypatcha**. Usa `to_prepare` no engine.rb pra injetar associações:

```ruby
# plugins/telemed/lib/telemed/engine.rb
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
```

Tudo o mais é tabela própria (`telemed_recordings`, `proposed_evolutions`, `telemed_consents`) + FK pra tabelas existentes (`accounts`, `patients`, `agenda_events`, `session_logs`).

**Implicação pra replicação**: você não precisa modificar models do core — só criar 3 tabelas novas + 1 FK em `session_logs` (coluna `proposed_evolution_id`).

---

## 1.6 ActionCable broadcasts (real-time UI)

Após cada transição de status (`pending → recording → uploaded → transcribing → transcribed → evolving → ready` ou `failed`), o `TelemedRecording#broadcast_status_change!` publica no canal `account_<id>`:

```json
{
  "event": "telemed.recording.status_changed",
  "data": {
    "agenda_event_id": 86,
    "recording_id": 96,
    "status": "ready",
    "has_transcript": true,
    "has_audio": true
  }
}
```

O dashboard tem um listener global (`onTelemedRecordingUpdated`) que refaz `fetchDetail` em transições terminais (`transcribed`, `ready`, `failed`). Sem isso, a UI ficaria stale em "Gravação em processamento…" até F5 manual.

---

## 1.7 Idempotência e resiliência

- **Webhook egress**: chega 2-3x do LiveKit (retries). `find_or_create_by(egress_id:)` + `with_lock` na recording previne duplicatas.
- **Transcribe job**: 3 retries com `wait: :exponentially_longer`. Falha permanente (`PermanentFailure` pra arquivo > 25MB) descarta sem retry.
- **Generate evolution job**: 3 retries. Falha permanente (transcript > 600k chars) descarta.
- **Approve evolution**: transação única — ou cria `SessionLog` + marca evolution `approved` em bloco, ou nada muda.
- **Unique partial index**: `proposed_evolutions` tem index único parcial `(telemed_recording_id) WHERE status = 'pending_review'` — impede 2 propostas pendentes simultâneas (race em re-enqueue).

---

## 1.8 Resumo: o que é proprietário vs reutilizado

| Camada | Origem |
|--------|--------|
| Sala WebRTC | LiveKit (external service) |
| Storage de áudio | Cloudflare R2 (external service) |
| Transcrição | OpenAI `gpt-4o-transcribe-diarize` (external API) |
| IA clínica | Anthropic Claude (external API, via `ruby_llm` gem) |
| Orquestração (jobs, webhooks, services) | **Código próprio** (`plugins/telemed/app/`) |
| Sala UI (vídeo, controles, blur, waiting room) | **Código próprio** (`TelemedicineRoom.vue`) usando SDK LiveKit |
| Dashboard (lista, detalhe, transcrição, evolução) | **Código próprio** |
| Persistência (`TelemedRecording`, `ProposedEvolution`) | **Código próprio** |
| Prontuário (`SessionLog`) | Core Klivy (apenas referenciado) |
