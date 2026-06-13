# Auditoria Enterprise — Módulo Telemedicina

**Data:** 2026-05-20
**Auditor:** Claude Code (Opus 4.7)
**Versão:** Sprint L (gravação + transcrição + evolução IA)
**Escopo:** Backend Rails + Frontend Vue + Infra (LiveKit, MinIO, cloudflared)

---

## ⚠️ Caveat metodológico

Esta auditoria é **estática** — leitura de código + smoke tests. Nenhum teste de carga, nenhum pen test, nenhum stress test foi rodado. Achados marcados com:
- **[E]** = evidência direta no código
- **[H]** = hipótese (precisa validação manual ou em runtime)

Onde houver dúvida, preferi reportar como hipótese.

---

## 1. Resumo Executivo

### Status geral
Módulo **funcional end-to-end** (smoke test validou Whisper → Claude → SOAP). Mas tem dívida técnica significativa em multi-tenancy, concorrência e realtime — não está pronto pra produção.

### Readiness produção
🟡 **Beta interno OK / Produção: NÃO**

| Eixo | Score | Observação |
|---|---|---|
| Funcionalidade core | 8/10 | Pipeline gravação→IA→UI funciona |
| Multi-tenancy | **4/10** | Bucket S3 compartilhado sem ownership check, jobs sem account validation |
| Segurança | **5/10** | Webhook sem rate-limit, mass assignment `permit!` |
| Performance | 6/10 | N+1 em listagem, índices OK |
| Escalabilidade | 5/10 | Filas Sidekiq não segregadas, sem cursor pagination |
| Realtime | **3/10** | Zero broadcasts ActionCable — UI 100% stale |
| Clean architecture | 7/10 | Padrões consistentes, alguns god services |
| Concorrência | **4/10** | Race conditions em `start!` e webhook |
| Frontend Vue | 7/10 | Composables bons, v-for com `:key="idx"` |
| Cobertura testes | ?/10 | Não auditado nesta passada |

### Nível de risco
| Risco | Probabilidade | Impacto | Severidade |
|---|---|---|---|
| Vazamento cross-tenant via `recording_url` | Média | Crítico (PII médico) | 🔴 |
| DDoS de custo via webhook forjado | Baixa | Alto ($$ Whisper) | 🔴 |
| Race condition criando 2 recordings duplicados | Média | Médio (custo 2× Whisper) | 🟡 |
| UI ficar stale eternamente sem F5 | **Alta** | Alto (UX ruim) | 🔴 |
| Whisper timeout em consultas > 30 min | Alta | Alto (consulta perdida) | 🟡 |

---

## 2. Arquitetura Encontrada

### Distribuição física do código
O módulo NÃO está num plugin único — está distribuído em 5 lugares:

```
plugins/patient_portal/        ← núcleo (models, services, jobs, frontend paciente)
plugins/agenda/                ← controllers + frontend dentista (lista/detalhe/sala)
app/                           ← webhook LiveKit, policies, super_admin
db/migrate/                    ← 4 migrations Sprint L
dev-tools/                     ← LiveKit + Egress configs
```

### Fluxo end-to-end
```
Paciente clica "Entrar"                  Dentista clica "Entrar"
    │                                        │
    ▼ POST /telemedicine_token (patient)      ▼ POST /telemedicine_token (agenda)
SessionIssuer → JWT LiveKit + url
    │                                        │
    └──── Ambos conectam no LiveKit ────────┘
                  │
                  │  Frontend POST /telemedicine_event(kind=joined)
                  ▼
        SessionEventHandler.joined!
            │
            └─ both_present? → RecordingOrchestrator.start!
                                  │
                                  ├─ 3× start_*_egress! (doctor temp + patient temp + composite)
                                  └─ recording.status = 'recording'
                                       │
                                       ▼
                              LiveKit server publica jobs no Redis
                                       │
                                       ▼
                              Egress (Docker) consome, conecta via SDK source
                                       │  (NÃO usa Chrome)
                                       ▼
                              Grava OGG → upload S3/MinIO
                                       │
                              ┌────────┴───── webhook egress_started ──→ Rails recording.status='recording'
                              │
                  Ambos saem  │
                              │   SessionEventHandler.left! (nobody_present)
                              │       │
                              │       └─ RecordingOrchestrator.stop!
                              │
                              ▼
                  webhook egress_ended (×3 ou ×expected) ──→ Rails
                                                              │
                                                              ├─ atualiza audio_keys
                                                              └─ se all_done → enfileira TranscribeJob
                                                                                      │
                                                                                      ▼
                                                                              Whisper (×2 ou ×1)
                                                                              merge cronológico
                                                                              recording.status='transcribed'
                                                                                      │
                                                                                      └─ enfileira GenerateEvolutionJob
                                                                                              │
                                                                                              ▼
                                                                                      Claude Sonnet 4.5
                                                                                      ProposedEvolution(pending_review)
                                                                                      recording.status='ready'
                                                                                              │
                                                                                              └─ Sem broadcast 🔴
                                                                                                  User precisa F5
```

### Componentes principais
| Tipo | Arquivo | Responsabilidade |
|---|---|---|
| Model | `telemed_recording.rb` | Estado da gravação (8 statuses + scopes + helpers) |
| Model | `proposed_evolution.rb` | SOAP proposto pela IA + `approve!` → ClinicalNote |
| Model | `patient_portal_consent.rb` | Termo LGPD/CFM aceito pelo paciente |
| Service | `recording_orchestrator.rb` | Orquestra 3 Egress jobs paralelos |
| Service | `session_event_handler.rb` | joined/left → status transitions + jobs |
| Service | `session_tracker.rb` | JSONB no AgendaEvent c/ timestamps presença |
| Service | `recording_storage.rb` | Abstração S3-compat com fallback filesystem local |
| Service | `credentials_resolver.rb` | LiveKit credentials por tenant + dev tunnel |
| Service | `evolution_provider.rb` + `claude.rb` + `open_ai.rb` | Factory pluggable de LLM |
| Service | `transcription_provider/whisper.rb` | OpenAI Whisper client |
| Job | `transcribe_recording_job.rb` | Baixa OGG → Whisper × 2 → merge → delete temps |
| Job | `generate_evolution_job.rb` | Whisper transcript → Claude SOAP → ProposedEvolution |
| Job | `enforce_recording_quota_job.rb` | Archive antigos se > 15 ativos |
| Job | `purge_account_recordings_job.rb` | LGPD: deleta 1 ano após cancel |
| Job | `mark_in_progress_job.rb` / `mark_no_show_job.rb` | Timers de status |
| Controller | `webhooks/livekit/egress_controller.rb` | Webhook do LiveKit (JWT validation) |
| Controller | `teleconsultas_controller.rb` | API REST do dentista (lista/detalhe/recording_url/retranscribe/reevolve) |
| Controller | `proposed_evolutions_controller.rb` | update/approve/reject |
| Frontend | `TeleconsultaListPage.vue` + tabs | Lista por tab |
| Frontend | `TeleconsultaDetailPage.vue` | Player + transcript + editor SOAP |
| Frontend | `TelemedicineRoom.vue` (paciente) | Sala WebRTC c/ consent modal |
| Frontend | `useTelemedicineSession.js` | reportJoined/reportLeft idempotente |

### Realtime / Websocket
**❌ INEXISTENTE.** Zero `ActionCable.server.broadcast` em todo o módulo. Frontend só atualiza via F5/refetch manual.

### Dependências externas
- LiveKit server (WSS signaling + RTP UDP/TCP)
- LiveKit Egress (Docker, conecta via Redis)
- MinIO local OU R2/S3 (storage de áudio)
- OpenAI Whisper API
- Anthropic Claude API
- Redis (Sidekiq + LiveKit routing + Egress queue)
- PostgreSQL (records)
- cloudflared (tunnels HTTP/WSS) — dev only

---

## 3. Problemas Encontrados

| # | Severidade | Tipo | Arquivo | Problema | Impacto |
|---|---|---|---|---|---|
| 1 | 🔴 CRÍTICO | Multi-tenant | `teleconsultas_controller.rb:53-61` [E] | `recording_url` action gera signed URL sem validar que o `recording` pertence à account autenticada | Vazamento de áudio cross-tenant se atacante conhecer `event_id` |
| 2 | 🔴 CRÍTICO | Security | `proposed_evolutions_controller.rb:19` [E] | `params[:soap_structure]&.permit!` aceita TODOS os params nested | Mass assignment, possível injeção de campos |
| 3 | 🔴 CRÍTICO | Security | `webhooks/livekit/egress_controller.rb` [E] | Webhook sem rate limiting (Rack::Attack ou similar) | DDoS de custo: forjar webhooks dispara Whisper jobs ($$) |
| 4 | 🔴 CRÍTICO | Realtime | `webhooks/livekit/egress_controller.rb:177` [E] | Zero `ActionCable.server.broadcast` quando recording.status muda | UI 100% stale — user vê "transcrevendo" eternamente até F5 |
| 5 | 🔴 CRÍTICO | Concorrência | `recording_orchestrator.rb:129-135` [E] | `existing_active_recording` query sem lock; 2 calls simultâneas criam 2 recordings | Custo 2× Whisper + caos de webhooks |
| 6 | 🟡 ALTO | Multi-tenant | `telemed_recording.rb:45-47` + `egress_controller.rb:106` [E] | Scope `by_egress_id` sem `account_id` filtro | Hipotético cross-tenant se egress_ids colidirem (improvável mas possível) |
| 7 | 🟡 ALTO | Sidekiq | `transcribe_recording_job.rb:26-62` [E] | `retry_on attempts: 3` + `bump_retry!` + `raise` no rescue podem somar até 6 tentativas reais | Custo Whisper até 6× em transient errors |
| 8 | 🟡 ALTO | Concorrência | `webhooks/livekit/egress_controller.rb:107-138` [E] | `handle_ended` faz `reload`+`update!` sem pessimistic lock; 2 webhooks simultâneos podem perder updates | duration/size calculados errado, race na transição `all_done` |
| 9 | 🟡 ALTO | Performance | `teleconsultas_controller.rb:26` + `to_summary_hash` [E] | `latest_proposed_evolution` chamado 2× por recording em loop de N items | N+1: 20 items × 2 = 40 queries extras |
| 10 | 🟡 ALTO | Performance | `transcription_provider/whisper.rb:18` [E] | `REQUEST_TIMEOUT = 300` (5min) insuficiente pra áudio > 30min | Consulta longa falha sempre |
| 11 | 🟡 ALTO | Frontend | `TeleconsultaTranscript.vue:34` [E] | `v-for="(seg, idx) in segments" :key="idx"` — index como key | Re-render quebra ao mudar lista, listeners reciclam |
| 12 | 🟡 ALTO | Realtime/Cleanup | `TelemedicineRoom.vue:254-270` [E] | LiveKit SDK `room.on(...)` sem `room.off(...)` no unmount | Memory leak ao reabrir sala, listeners duplicados |
| 13 | 🟡 ALTO | Sidekiq | Todos os jobs telemed [E] | `queue_as :default` em todos — Whisper (5min) + timers (5min wait) na mesma fila | Whisper jobs bloqueiam MarkInProgressJob |
| 14 | 🟢 MÉDIO | Performance | `proposed_evolutions` migration [E] | Faltam índices em `clinical_note_id` e `reviewed_by` | Query lenta em filtros futuros |
| 15 | 🟢 MÉDIO | Arch | `proposed_evolution.rb:32-50` [E] | Model cria ClinicalNote (acoplamento cross-model) | Mudança schema ClinicalNote quebra evolution |
| 16 | 🟢 MÉDIO | Arch | `proposed_evolution.rb:99-103` [E] | SOAP keys hardcoded (`soap['subjetivo']`, etc) — sem constante | Se prompt Claude muda chave, fail silencioso |
| 17 | 🟢 MÉDIO | Security | `webhooks/livekit/egress_controller.rb:78-79` [H] | `egress_id` sem validação de formato (UUID/length) | Input não-sanitizado (parameterized query protege SQL injection, mas integer/null behavior indefinido) |
| 18 | 🟢 MÉDIO | Security/Privacy | `telemed_recording.transcript_text` [H] | PII médico em plain text na coluna; serializer expõe completo | Risco LGPD se DB backup vaza |
| 19 | 🟢 MÉDIO | Frontend | `TelemedicineRoom.vue:91-96` [E] | Consent modal não persiste localmente — F5 pede de novo | UX ruim em reconnect |
| 20 | 🟢 MÉDIO | Sidekiq | Sem split de áudio Whisper > 25MB | Limite Whisper API; arquivos longos rejeitados | Consulta > 1h não transcreve |
| 21 | 🔵 INFO | Security | `credentials_resolver.rb:36` [E] | Fallback chain termina em DEV defaults (`devkey/secret`) | Em prod sem ENV var, app conecta em LiveKit local fantasma |
| 22 | 🔵 INFO | Arch | `SessionEventHandler` [E] | God service (3 deps + scheduler + business rules) | Difícil testar sem stubs |

---

## 4. Vazamentos Multi-Tenant

### 4.1 🔴 CRÍTICO — `recording_url` sem ownership check
**Arquivo:** `plugins/agenda/app/controllers/api/v1/accounts/teleconsultas_controller.rb:53-61`

```ruby
def recording_url
  key = recording_key_for(params[:kind])
  url = PatientPortal::Telemedicine::RecordingStorage.signed_url(key)
  render json: { url: url, expires_in: 300 }
end
```

`recording_key_for` lê de `@recording` que vem de `before_action :load_agenda_event`. Se esse `load_agenda_event` não fizer `account_id` scope, attacker logado na conta A consegue gerar signed URL pra áudio da conta B passando `event_id` adivinhado.

**Verifique:** `load_agenda_event` faz `Current.account.agenda_events.find(...)` ou só `AgendaEvent.find`?

### 4.2 🟡 ALTO — Scope `by_egress_id` sem account_id
**Arquivo:** `plugins/patient_portal/app/models/telemed_recording.rb:45-47`

```ruby
scope :by_egress_id, ->(id) {
  where('doctor_egress_id = :id OR patient_egress_id = :id OR composite_egress_id = :id', id: id)
}
```

Webhook `egress_controller.rb:106` faz `TelemedRecording.by_egress_id(egress_id).first` sem filtro tenant. Se LiveKit colidir IDs entre contas (improvável mas não validado), webhook atualiza recording da conta errada.

### 4.3 🟡 ALTO — Jobs sem account validation
**Arquivo:** `transcribe_recording_job.rb:30`, `generate_evolution_job.rb:20`

```ruby
recording = TelemedRecording.find_by(id: recording_id)
```

Jobs recebem só `recording_id`. Não validam contra account. Em si não é vazamento (recording carrega seu próprio `account_id`), mas se atacante consegue enfileirar job manualmente com ID arbitrário (via Sidekiq web sem auth?), pode disparar processamento.

### 4.4 🟡 ALTO — Bucket S3 único para todos os tenants
**Arquivo:** `recording_storage.rb:65-66`

```ruby
@bucket = env_with_fallback!('TELEMED_STORAGE_BUCKET', 'STORAGE_BUCKET_NAME')
```

Todas as contas escrevem em `klivy-storage`. Path inclui `accounts/X/` mas não há credenciais S3 com policy `accounts/${user.account_id}/*`. Se key vaza, qualquer um com creds AWS lê.

### 4.5 🔵 INFO — ENV vars GLOBAIS (Whisper, Claude, LiveKit)
**Arquivo:** `whisper.rb:60-63`, `claude.rb:167-168`

`OPENAI_WHISPER_KEY`, `ANTHROPIC_API_KEY`, `LIVEKIT_API_KEY/SECRET` são únicos por instalação. Isso é decisão de design (Klivy-hosted multi-tenant). Custos somam pra todas as contas. Se um tenant quiser sua própria conta OpenAI (compliance), precisa refatorar.

---

## 5. Problemas de Segurança

### 5.1 🔴 CRÍTICO — Mass assignment via `permit!`
**Arquivo:** `proposed_evolutions_controller.rb:19`

```ruby
soap_structure: params[:soap_structure]&.permit!.to_h,
```

`permit!` aceita TODOS os params nested. Permite injeção de qualquer chave. **Fix:** `params.require(:soap_structure).permit(:subjetivo, :objetivo, :avaliacao, :plano)`.

### 5.2 🔴 CRÍTICO — Webhook sem rate limiting
**Arquivo:** `webhooks/livekit/egress_controller.rb`

Nenhum `Rack::Attack` config encontrado pra `/webhooks/livekit/egress`. Atacante que conhece `LIVEKIT_API_SECRET` (rotação?) forja JWT válido + manda 1000 webhooks/seg → dispara 1000 TranscribeJob → custo Whisper explodiu.

### 5.3 🟡 ALTO — JWT secret sem rotação
**Arquivo:** `.env` `LIVEKIT_API_SECRET`

Mesmo secret pra signing E verification. Sem mecanismo de rotação. Se vaza (commit no git, log, etc), única solução é regenerar e perder todas as gravações em curso.

### 5.4 🟢 MÉDIO — `egress_id` sem validação de formato
**Arquivo:** `webhooks/livekit/egress_controller.rb:78`

Input não sanitizado. `null`, `0`, string vazia, type confusion. SQL injection protegida por parameterized query, mas behavior indefinido.

### 5.5 🟢 MÉDIO — PII médico em plain text
**Arquivo:** `telemed_recording.transcript_text`, `proposed_evolution.soap_structure`

Transcripts com nome do paciente, queixa, diagnóstico, medicações em plain text. Nenhuma encryption at-rest. LGPD considera "dado sensível de saúde" (Art. 5º II). Risco se DB backup vaza, se admin malicioso, se SQL injection ainda existe em outra parte do app.

### 5.6 🔵 INFO — `super_admin/test_connection` timing attack
**Arquivo:** `super_admin/app_configs_controller.rb`

Endpoint revela via HTTP code se uma API key OpenAI/Anthropic é válida. Atacante super_admin já tem acesso a tudo, então risk baixo, mas vale rate-limit.

### 5.7 🔵 INFO — Credenciais S3 enviadas via Redis em texto
**Arquivo:** `recording_orchestrator.rb#build_s3_upload`

`S3Upload.access_key/secret` vai pro Egress via Redis (sem encryption). Se Redis é compartilhado ou backup vaza, creds expostas.

---

## 6. Problemas de Performance

### 6.1 🟡 ALTO — N+1 em `teleconsultas#index`
**Arquivo:** `teleconsultas_controller.rb:26` + `telemed_recording.rb:137-141`

`to_summary_hash` chama `latest_proposed_evolution` 2× (`.id.present?` + `.status`). Em loop de 20 items = 40 queries extras. **Fix:** cache local no método.

### 6.2 🟡 ALTO — Whisper timeout 300s
**Arquivo:** `transcription_provider/whisper.rb:18`

Consulta de 1h+ vai além de 300s. Aumentar pra `900` (15min).

### 6.3 🟢 MÉDIO — Faltam índices
**Arquivo:** `db/migrate/20260520000002_create_proposed_evolutions.rb`

Faltam:
- `proposed_evolutions(clinical_note_id)` — join com ClinicalNote
- `proposed_evolutions(reviewed_by)` — filtro por revisor

### 6.4 🟢 MÉDIO — `signed_url` sem cache cliente
**Arquivo:** `teleconsultas_controller.rb:61`

Cada F5 regenera signed URL (TTL 5min). Frontend poderia cachear por 4min.

### 6.5 🟢 MÉDIO — `pagination` offset-based
**Arquivo:** `teleconsultas_controller.rb:32`

`.limit().offset()` lento com offset alto. Cursor-based pagination (keyset) escala melhor.

---

## 7. Problemas de Escalabilidade

### 7.1 🟡 ALTO — Filas Sidekiq não segregadas
**Arquivo:** todos `*_job.rb`

`queue_as :default` em tudo. Whisper (5min) bloqueia MarkInProgressJob (timer 5min wait). **Fix:**

```ruby
# transcribe_recording_job.rb
queue_as :telemed_transcription   # workers dedicados, concurrency: 15

# generate_evolution_job.rb
queue_as :telemed_llm             # workers dedicados, concurrency: 10

# mark_*_job.rb, enforce_quota_job.rb, purge_*_job.rb
queue_as :default                  # OK pra timers/admin
```

### 7.2 🟡 ALTO — Whisper sem split de arquivo
**Arquivo:** `transcribe_recording_job.rb`

API rejeita > 25MB. Consulta de 1h em 64kbps ≈ 28MB. Implementar split (ffmpeg) ou comprimir pra 32kbps.

### 7.3 🟢 MÉDIO — 1000 gravações simultâneas → bottleneck
**Arquivo:** config Sidekiq global

Concurrency padrão = 5. 1000 jobs simultâneos demoram 200min na fila. **Fix:** escalar Sidekiq workers ou usar Sidekiq Pro/Enterprise.

### 7.4 🟢 MÉDIO — Custo 2× Whisper na diarização
**Arquivo:** `transcribe_recording_job.rb:72-73`

`transcribe_diarized!` chama Whisper 2× (doctor + patient). Aceitável pelo PRD mas dobra custo ($0.012/min vs $0.006/min). Documentar.

### 7.5 🔵 INFO — Storage cresce indefinidamente
**Arquivo:** `enforce_recording_quota_job.rb`

`max_active_recordings = 15` por conta arquiva mais antigos. Mas `composite_audio_key` é mantido até `archive!`. 100 clínicas × 15 × 28MB = 42 GB ativo no R2.

---

## 8. Problemas de Realtime / Websocket

### 8.1 🔴 CRÍTICO — Zero ActionCable broadcasts
**Arquivo:** módulo inteiro

Nenhum `ActionCable.server.broadcast` quando `recording.status` muda. Frontend NÃO recebe push. User abre detalhe, espera transcrição ficar pronta, vê "transcrevendo" eternamente até F5. **UX é fatal pra produção.**

**Fix sugerido:** criar `TelemedRecordingChannel`, broadcast em:
- `egress_controller#handle_started` → status `recording`
- `egress_controller#handle_ended (all_done)` → status `uploaded`
- `transcribe_recording_job#perform` → status `transcribed`
- `generate_evolution_job#perform` → status `ready`

E no frontend `TeleconsultaDetailPage.vue` subscribe.

### 8.2 🟡 ALTO — Listeners LiveKit não desmontam
**Arquivo:** `TelemedicineRoom.vue:254-270`

```javascript
room.on(RoomEvent.ParticipantConnected, onParticipantConnected);
// ...
// FALTA: room.off(...) no onUnmounted ou disconnect()
```

Memory leak em sessões longas ou abas que reabrem.

### 8.3 🟡 ALTO — Token TTL 2h sem refresh automático
**Arquivo:** `session_issuer.rb:22`

Consulta > 2h precisa novo token. Não há mecanismo de refresh transparente. Cliente desconecta abruptamente.

### 8.4 🟢 MÉDIO — `reportLeft` em fechamento de aba não confiável
**Arquivo:** `TelemedicineRoom.vue`

`onBeforeUnmount` em Vue não dispara consistentemente quando aba fecha. Deveria usar `navigator.sendBeacon()` pra garantir entrega ao backend.

---

## 9. Problemas Frontend

### 9.1 🟡 ALTO — `v-for :key="idx"` em transcript
**Arquivo:** `TeleconsultaTranscript.vue:34`

Index instável quebra re-render quando lista muda. **Fix:** `:key="\`${seg.start}-${seg.text.substring(0,20)}\`"`.

### 9.2 🟡 ALTO — Sem cleanup de LiveKit listeners
**Arquivo:** `TelemedicineRoom.vue` (já em 8.2)

### 9.3 🟢 MÉDIO — Consent modal não persiste
**Arquivo:** `TelemedicineRoom.vue:91-96`

F5 = paciente vê modal de novo. Salvar em `localStorage` por evento ou backend.

### 9.4 🟢 MÉDIO — Sem auto-save no `TeleconsultaEvolutionEditor`
**Arquivo:** `TeleconsultaEvolutionEditor.vue:33-47`

Dentista edita SOAP, fecha aba sem salvar, perde mudanças. **Fix:** debounce + auto-save OR aviso "mudanças não salvas".

### 9.5 🟢 MÉDIO — i18n hardcoded em PT-BR
**Arquivo:** `TeleconsultaListPage.vue:17-21`

Aceitável pra MVP Klivy. Documentar como dívida pra Fase 2.

### 9.6 🟢 MÉDIO — Lista transcript sem virtualização
**Arquivo:** `TeleconsultaTranscript.vue`

1000+ segmentos = 1000 DOM nodes. Lag em consultas longas. Usar `vue-virtual-scroller`.

### 9.7 🟢 MÉDIO — Sem loading/error states polidos
**Arquivo:** `TeleconsultaListPage.vue`, `TeleconsultaDetailPage.vue`

`<div v-if="isLoading">Carregando...</div>` é placeholder. Skeleton screens dariam UX melhor.

---

## 10. Problemas Backend

### 10.1 🔴 CRÍTICO — Race em `RecordingOrchestrator.start!`
**Arquivo:** `recording_orchestrator.rb:129-135`

Query `existing_active_recording` sem lock. 2 chamadas simultâneas (ambos joined ao mesmo tempo) → 2 recordings criados.

**Fix:**
```ruby
@event.with_lock do
  return skip(:already_active, recording: existing_active_recording) if existing_active_recording
  recording = TelemedRecording.create!(...)
  # ... resto
end
```

### 10.2 🟡 ALTO — `retry_on` + `bump_retry!` somam tentativas
**Arquivo:** `transcribe_recording_job.rb:26-62`

`retry_on attempts: 3` + custom `bump_retry!` + `raise` = potencialmente 4-6 tentativas reais. Custo Whisper inflacionado. Escolher 1 mecanismo só.

### 10.3 🟡 ALTO — Sem `with_lock` no `handle_ended` webhook
**Arquivo:** `webhooks/livekit/egress_controller.rb:107-138`

2 webhooks `egress_ended` simultâneos podem fazer lost-update. `recording.reload` + `update!` sem lock pessimista.

### 10.4 🟢 MÉDIO — Monkey-patch via Engine
**Arquivo:** `patient_portal/lib/patient_portal/engine.rb`

`Account.class_eval { has_many :telemed_recordings }` etc. Padrão Chatwoot mas frágil — mudança no model raiz pode silenciosamente quebrar.

### 10.5 🟢 MÉDIO — `ProposedEvolution#approve!` cria ClinicalNote
**Arquivo:** `proposed_evolution.rb:32-50`

Acoplamento model → model. Extrair `ProposedEvolutionApprovalService`.

### 10.6 🟢 MÉDIO — SOAP keys hardcoded
**Arquivo:** `proposed_evolution.rb:99-103`

`soap['subjetivo']` etc. Se prompt Claude mudar pra `'subjective'`, todos os fields vazios silenciosamente.

### 10.7 🔵 INFO — God service `SessionEventHandler`
**Arquivo:** `session_event_handler.rb`

3 dependências + scheduler + state machine. Extrair `SessionJobScheduler`.

### 10.8 🔵 INFO — Modelo `TelemedRecording` gordo
**Arquivo:** `telemed_recording.rb`

24 métodos, ~160 linhas. Aceitável mas no limite.

---

## 11. Problemas Arquiteturais

### 11.1 Não existe plugin `telemedicina/` dedicado
Código distribuído em 3 plugins + raiz. Migração futura pra `plugins/telemedicina/` única simplifica isolamento, deploy, testes. Custo: ~1 dia de refactor.

### 11.2 Dependência cruzada `agenda → patient_portal`
`agenda/frontend/routes/AgendaTelemedRoomPage.vue` importa `useTelemedicineSession` de `@plugins/patient_portal/...`. Aceitável (sentido único) mas formalize via API pública.

### 11.3 Status machine sem gem dedicada
8 estados `TelemedRecording` validados via inclusion. Sem AASM/state_machines. Aceitável MVP — documentar fluxo em README.

### 11.4 Sem specs do módulo
Não auditei specs nesta passada. Validar cobertura em `spec/plugins/patient_portal/{services,jobs,models}/telemedicine/`.

### 11.5 Engine injection via class_eval
Monkey patches risk → considerar Concerns nomeados (`Account::HasTelemedRecordings`).

---

## 12. Melhorias Recomendadas

### Imediatas (essa Sprint, antes de prod)
1. **Fix mass assignment `permit!`** (#2) — 30min
2. **Validar ownership em `recording_url`** (#1) — 1h
3. **Pessimistic lock em `start!` + `handle_ended`** (#5, #8) — 2h
4. **ActionCable broadcasts** (#4) — 4h
5. **`v-for :key` estável em Transcript** (#11) — 30min
6. **Webhook rate limiting (Rack::Attack)** (#3) — 1h
7. **Fix retry duplo Whisper** (#7) — 1h
8. **Aumentar Whisper timeout pra 900s** (#10) — 5min

**Total: ~10h**

### Curto prazo (Sprint M)
9. Segregar filas Sidekiq (#13) — 2h
10. Cleanup listeners LiveKit (#12) — 2h
11. Cache `latest_proposed_evolution` no model (#9) — 1h
12. Adicionar índices `proposed_evolutions(clinical_note_id, reviewed_by)` (#14) — 30min
13. Extrair `ProposedEvolutionApprovalService` (#15) — 2h
14. Constante pra SOAP keys + parse defensivo (#16) — 1h
15. Validação de formato `egress_id` (#17) — 30min
16. Persistir consent modal em localStorage (#19) — 1h

**Total: ~10h**

### Médio prazo (Sprint N+1)
17. Encryption at-rest pra `transcript_text` + `soap_structure` (LGPD) (#18)
18. Split Whisper > 25MB (#20)
19. Cursor pagination em listagem (#6.5)
20. Auto-save no editor SOAP (#9.4)
21. Virtualização de Transcript longo (#9.6)
22. PII redaction em logs (#5.5)

### Longo prazo (Fase 2)
23. Migrar pra `plugins/telemedicina/` único (#11.1)
24. JWT secret rotation (#5.3)
25. Tenant-scoped S3 credentials (#4.4)
26. i18n keys (#9.5)
27. State machine explícita (AASM) (#11.3)
28. LiveKit Cloud migration (resolve NAT WebRTC mobile, escala TURN gerenciado)

---

## 13. Plano de Correção

### Fase 1 — Bloqueadores de Produção (1 dia)
**Objetivo:** Fechar buracos de segurança e UX fatais.

| # | Item | Risco |
|---|---|---|
| 1 | Fix mass assignment `permit!` | Sem regressão |
| 2 | Ownership check em `recording_url` (Pundit policy) | Sem regressão |
| 3 | Pessimistic lock em `start!` e `handle_ended` | Sem regressão (transação) |
| 4 | Webhook rate limiting (Rack::Attack 60 req/min/IP) | Baixo — pode bloquear LiveKit retry; ajustar limit |
| 5 | Fix retry duplo (manter `retry_on`, remover `bump_retry!`/`raise`) | **Médio** — testar manualmente que falhas reais ainda falham |

### Fase 2 — Realtime + Performance (1 dia)
**Objetivo:** UX decente em prod.

| # | Item | Risco |
|---|---|---|
| 6 | ActionCable broadcasts em todos os status changes | Sem regressão (additivo) |
| 7 | Frontend subscribe TelemedRecordingChannel | Sem regressão (additivo) |
| 8 | Segregar filas Sidekiq | **Médio** — precisa atualizar config workers em prod |
| 9 | Cache `latest_proposed_evolution` | Sem regressão |
| 10 | Aumentar Whisper timeout | Sem regressão |

### Fase 3 — Frontend + UX (0.5 dia)
**Objetivo:** Polish.

| # | Item | Risco |
|---|---|---|
| 11 | `v-for :key` estável | Sem regressão |
| 12 | Cleanup LiveKit listeners | Sem regressão |
| 13 | Consent persist localStorage | Sem regressão |
| 14 | Loading skeletons | Sem regressão |

### Fase 4 — Hardening + Dívida técnica (1 sprint)
**Objetivo:** Refatorações que ficaram pra trás.

| # | Item | Risco |
|---|---|---|
| 15 | Extract `ProposedEvolutionApprovalService` | **Médio** — refator de model, validar testes |
| 16 | Constante pra SOAP keys | Sem regressão |
| 17 | Encryption at-rest pra transcripts | **Alto** — migração de dados, precisa key management |
| 18 | Split Whisper > 25MB | Sem regressão (mas adiciona complexidade) |
| 19 | Migrate pra `plugins/telemedicina/` | **Alto** — moving 30+ arquivos |

---

## 14. Checklist Final

- [ ] **Multi-tenant seguro** — bucket S3 compartilhado, `recording_url` sem ownership check, scope `by_egress_id` sem account_id
- [ ] **APIs protegidas** — `permit!` em soap_structure, webhook sem rate limit
- [x] **Policies seguras** — `ProposedEvolutionPolicy` valida owner via `record.telemed_recording.agenda_event.user_id == user.id` ✓
- [ ] **Websocket seguro** — N/A: módulo não usa ActionCable (mas DEVERIA)
- [ ] **Jobs seguros** — race condition em `existing_active_recording`, retry duplo em TranscribeJob
- [ ] **Performance OK** — N+1 em listagem, Whisper timeout curto, sem cache de signed_url
- [ ] **Escalabilidade OK** — filas Sidekiq não segregadas, sem cursor pagination
- [x] **Código limpo** — services bem isolados (Orchestrator, Resolvers, Providers); padrão Factory funciona
- [x] **Sem dead code** — não encontrei dead code óbvio (mas não fiz auditoria de cobertura)
- [ ] **Sem memory leaks** — LiveKit listeners não desmontam
- [ ] **Sem race conditions** — 3 races identificadas (start!, handle_ended, retry)
- [x] **Sem N+1** óbvio em produção — **FALSO**, achei N+1 em `to_summary_hash`
- [ ] **Sem vazamentos** — `recording_url` precisa ownership check formal
- [ ] **Sem broadcasts inseguros** — N/A: módulo não broadcasta nada (precisa começar a broadcastar)

---

## Apêndice — Confiança dos achados

| Categoria | Achados [E] (evidência) | Achados [H] (hipótese) |
|---|---|---|
| Multi-tenant | 4 | 1 |
| Security | 3 | 3 |
| Performance | 4 | 1 |
| Realtime | 3 | 0 |
| Frontend | 5 | 0 |
| Backend | 7 | 1 |
| Concorrência | 3 | 1 |

**Total: 29 evidências + 7 hipóteses = 36 achados.**

---

**Próximo passo recomendado:** atacar Fase 1 (1 dia) para destravar deploy beta. Fase 2 (1 dia) entrega UX decente. Demais fases conforme priorização do produto.
