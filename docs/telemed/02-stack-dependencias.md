# 02 — Stack e Dependências

## 2.1 Versões base

| Camada | Versão |
|--------|--------|
| Ruby | 3.4.4 |
| Rails | 7.1.5.2 |
| PostgreSQL | 14+ (jsonb obrigatório) |
| Redis | 7+ (Sidekiq + ActionCable) |
| Node | 20+ |
| Vue | 3.x (Composition API com `<script setup>`) |
| Vite | usado pelo Klivy core |

---

## 2.2 Gems Ruby (`Gemfile`)

| Gem | Versão | Propósito | Onde é usada |
|-----|--------|-----------|--------------|
| `livekit-server-sdk` | `~> 0.9` | SDK Ruby pra criar tokens JWT, configurar Egress, gerenciar Room/Participant. | `Telemed::SessionIssuer`, `Telemed::RecordingOrchestrator` |
| `jwt` | (latest) | Validar HS256 signature do webhook LiveKit Egress. | `Webhooks::Livekit::EgressController` |
| `aws-sdk-s3` | (latest, `require: false`) | Cliente S3-compatible pra Cloudflare R2 (download/signed URL/delete). | `Telemed::RecordingStorage` |
| `ruby_llm` | `>= 1.8.2` | Wrapper PT-BR-friendly pro Anthropic SDK; abstrai múltiplos providers (Claude, OpenAI, Gemini). | `Telemed::EvolutionProvider::Claude` |
| `ruby_llm-schema` | (latest) | Schemas opcionais pra parsing estruturado (não usado ativamente — preferimos parser próprio). | — |
| `ruby-openai` | (latest) | Cliente Ruby pra OpenAI API. | `Telemed::TranscriptionProvider::Gpt4oDiarize` |
| `sidekiq` | 7+ (Klivy core) | Workers async (transcribe, generate evolution, mark no-show). | `Telemed::*Job` |

**Não precisa** instalar: pundit, jbuilder, kaminari — já vêm do core Klivy.

---

## 2.3 Pacotes NPM (`package.json`)

| Pacote | Versão | Propósito | Onde |
|--------|--------|-----------|------|
| `livekit-client` | `^2.19.0` | SDK JS oficial — Room, Track, RoomEvent, createLocalVideoTrack, etc. | `TelemedicineRoom.vue` |
| `@livekit/track-processors` | `^0.7.2` | Background blur (MediaPipe). Lazy-loaded por dynamic import. | `TelemedicineRoom.vue` |
| `vue-virtual-scroller` | (Klivy core) | Virtualização da transcrição (transcripts longos têm 100+ segmentos). | `TeleconsultaTranscript.vue` |
| `@vueuse/components` | `^12.0.0` | `vOnClickOutside` no menu de devices. | `TelemedicineRoom.vue` |
| `date-fns` + `date-fns-tz` | 2.21.1 + ^1.3.3 | Formatação `DD/MM/YYYY às HH:mm` com fuso America/Sao_Paulo. | `utils/formatters.js` |
| `markdown-it` | (Klivy core) | Render do "Resumo Executivo" (único campo da IA com Markdown). | `TeleconsultaSummary.vue` |

**Não precisa**: axios, vuex, vue-router — core Klivy.

---

## 2.4 Variáveis de ambiente

### 2.4.1 LiveKit

| Var | Obrigatório | Exemplo | Origem |
|-----|-------------|---------|--------|
| `LIVEKIT_URL` | sim | `wss://livekit.exemplo.com` | LiveKit Cloud dashboard / self-host |
| `LIVEKIT_API_KEY` | sim | `APIxxx...` | LiveKit Cloud dashboard |
| `LIVEKIT_API_SECRET` | sim | `secretxxx...` | LiveKit Cloud dashboard |
| `LIVEKIT_WEBHOOK_KEY` | opcional | (fallback usa `LIVEKIT_API_KEY`) | Webhook signature validation |

### 2.4.2 Storage R2 (Cloudflare)

| Var | Obrigatório | Exemplo |
|-----|-------------|---------|
| `TELEMED_STORAGE_BUCKET` | sim | `klivy-telemed-recordings` |
| `TELEMED_STORAGE_ENDPOINT` | sim | `https://<account>.r2.cloudflarestorage.com` |
| `TELEMED_STORAGE_ACCESS_KEY_ID` | sim | `xxxxxxxxxxxx` |
| `TELEMED_STORAGE_SECRET_ACCESS_KEY` | sim | `xxxxxxxxxxxx` |
| `TELEMED_STORAGE_REGION` | opcional | `auto` (R2 ignora, mas SDK exige) |

**Bucket separado de ActiveStorage**. ACL: private. Lifecycle policy recomendada: delete após 30 dias (cobre janela de auditoria com folga).

### 2.4.3 IA

| Var | Obrigatório | Exemplo |
|-----|-------------|---------|
| `ANTHROPIC_API_KEY` | sim | `sk-ant-api03-...` |
| `OPENAI_API_KEY` | sim | `sk-proj-...` |
| `OPENAI_WHISPER_KEY` | opcional | (default usa `OPENAI_API_KEY`) |

### 2.4.4 Encryption (LGPD)

| Var | Obrigatório | Como gerar |
|-----|-------------|------------|
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | sim em prod | `bin/rails db:encryption:init` (gera 3 chaves; usar apenas a primary) |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | sim em prod | idem |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | sim em prod | idem |

Boot guard em `config/initializers/telemed.rb`:

```ruby
# Fail-fast: prod sem encryption key = morte na boot.
if Rails.env.production? && ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].blank?
  raise 'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ausente — telemed manipula PII clínica e exige encryption em prod.'
end
```

### 2.4.5 Domínios / multi-host (Patient Portal)

| Var | Exemplo |
|-----|---------|
| `FRONTEND_URL` | `https://app.klivy.com` (dashboard) |
| `PATIENT_PORTAL_URL` | `https://pacientes.klivy.com` (paciente) |

O patient portal monta no host `pacientes.*` (constraint regex em `plugins/patient_portal/config/routes.rb`).

---

## 2.5 Serviços externos

### 2.5.1 LiveKit

**O que faz**: provedor WebRTC SFU (Selective Forwarding Unit) — routeia áudio/vídeo entre participantes, grava (Egress), emite tokens JWT pra autorização.

**Opções**:
- **Cloud** (recomendado pra início): pay-per-minute. Painel em `cloud.livekit.io`. Cria projeto, copia API key/secret, configura webhook URL.
- **Self-host** (Docker): `docker-compose.livekit.yml` no repo (dev). Em prod: Kubernetes ou bare-metal. Requer TURN servers (LiveKit já provê via livekit-egress).

**Webhook URL** a configurar no LiveKit:
```
https://<seu-dominio>/webhooks/livekit/egress
```

Eventos relevantes que o LiveKit envia:
- `egress_started` — começou gravação
- `egress_ended` — terminou (success/failed)
- `track_published` — track de áudio publicado (capturamos `track_sid`)

### 2.5.2 Cloudflare R2

**O que faz**: storage S3-compatible, sem egress fees. Guarda os 3 arquivos `.ogg` por consulta.

**Setup**:
1. Cria bucket em `dash.cloudflare.com/r2`.
2. Gera API token com permissão `Read+Write` apenas no bucket criado.
3. Define lifecycle rule: deletar objetos com prefixo `telemed/` após 30 dias.
4. Copia endpoint `https://<accountid>.r2.cloudflarestorage.com`.

**Estrutura de chaves**:
```
telemed/
  account_<id>/
    event_<id>/
      doctor_<egress_id>.ogg
      patient_<egress_id>.ogg
      composite_<egress_id>.ogg
```

### 2.5.3 Anthropic API

**O que faz**: gera a evolução clínica (SOAP + 14 campos + pontos de atenção + resumo executivo) a partir da transcrição.

**Setup**: cria conta em `console.anthropic.com`, gera key. Limite mensal recomendado em prod: $500/mês (cobre ~8000 consultas).

**Modelo usado**: `claude-sonnet-4-6`. Trocável via `account.patient_portal_setting.telemedicine_recording['ai_provider']`. Configurado com `assume_model_exists: true` no `ruby_llm` pra aceitar modelos novos antes do registry estático do gem ser atualizado.

### 2.5.4 OpenAI API

**O que faz**: transcrição com diarização nativa via `gpt-4o-transcribe-diarize`.

**Por quê não Whisper**: o Whisper não tem diarização nativa (precisa de 2 chamadas com áudios isolados + merge cronológico). O `gpt-4o-transcribe-diarize` faz tudo em 1 chamada e tem WER 2.46% em PT-BR (vs ~5% Whisper).

**Modelo usado**: `gpt-4o-transcribe-diarize`. Mas o código mantém `Telemed::TranscriptionProvider::Whisper` como fallback caso o user prefira (configurável).

---

## 2.6 Cobertura de custos por consulta (estimativa MVP)

| Item | Custo médio (consulta 30min) |
|------|------------------------------|
| LiveKit Cloud (minutos audio/video) | ~$0.03 |
| LiveKit Egress | ~$0.02 |
| R2 storage (28MB × 30 dias) | ~$0.0001 |
| R2 operations (PUT/GET) | ~$0.001 |
| OpenAI gpt-4o-transcribe-diarize | ~$0.18 (30min × $0.006/min) |
| Anthropic Claude Sonnet (~3k in / 2k out tokens) | ~$0.06 |
| **TOTAL** | **~$0.30 / consulta** |

---

## 2.7 Setup local de desenvolvimento

Resumo (sem cobrir tudo do Klivy core):

```bash
# 1. Variáveis em .env (root do repo)
LIVEKIT_URL=wss://...
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
TELEMED_STORAGE_BUCKET=...
TELEMED_STORAGE_ENDPOINT=...
TELEMED_STORAGE_ACCESS_KEY_ID=...
TELEMED_STORAGE_SECRET_ACCESS_KEY=...
ANTHROPIC_API_KEY=...
OPENAI_API_KEY=...

# 2. Instalar deps
bundle install
pnpm install  # ou npm/yarn — Klivy usa pnpm

# 3. Migrations (essas + as do core)
bin/rails db:migrate

# 4. (Opcional dev) LiveKit local via Docker
docker-compose -f docker-compose.livekit.yml up

# 5. Boot
foreman start  # roda Rails + Sidekiq + Vite
```

Pra testar o webhook LiveKit em dev, expor o servidor com `ngrok http 3000` e configurar URL `https://abc123.ngrok.app/webhooks/livekit/egress` no painel LiveKit Cloud (ou na config self-host).

---

## 2.8 Quotas e rate limits

| Serviço | Limite default | Risco |
|---------|----------------|-------|
| Anthropic | 1000 req/min, 80k tokens/min | Médio (consultas geram bursts) |
| OpenAI transcribe | 50 req/min | Alto se múltiplas consultas terminam ao mesmo tempo |
| LiveKit Egress | 100 jobs simultâneos por projeto | Baixo |
| R2 storage | Sem limite | Baixo |

**Mitigação**: jobs Sidekiq em queue `:low` com concurrency limitada (`config/sidekiq.yml`), evita estourar quotas. `EnforceRecordingQuotaJob` arquiva gravações antigas pra limitar storage acumulado por conta (default 15 ativas).
