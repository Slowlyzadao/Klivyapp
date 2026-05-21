# PRD — Teleconsulta (Gravação + Transcrição + Evolução com IA)
## Product Requirements Document — Sprint L

**Produto:** Klivy / BeClinic — Módulo de Teleconsulta
**Base:** LiveKit (WebRTC), Cloudflare R2 (storage), OpenAI/Anthropic/Gemini (LLM)
**Sucessor de:** [agenda-teleconsulta.md](../03-engineering/agenda-teleconsulta.md) (Sprint K — sala + slug + automação de status)
**Data:** 2026-05-20
**Status:** Especificação técnica para início de desenvolvimento — destinada a iniciar Sprint L em nova sessão

---

## Índice

1. [Visão Executiva](#1-visao-executiva)
2. [Problema e Oportunidade](#2-problema-e-oportunidade)
3. [Estado Atual — o que já temos pronto](#3-estado-atual)
4. [Arquitetura Proposta](#4-arquitetura-proposta)
5. [Comparativo de Providers (gravação, transcrição, LLM)](#5-comparativo-de-providers)
6. [Nova Aba "Teleconsulta" no Menu Lateral](#6-nova-aba-teleconsulta)
7. [Modelo de Dados (novas tabelas + colunas)](#7-modelo-de-dados)
8. [APIs novas](#8-apis-novas)
9. [Pipeline Completo — sequência de eventos](#9-pipeline-completo)
10. [Fases de entrega (MVP / Fase 2 / Fase 3)](#10-fases-de-entrega)
11. [LGPD / CFM / Consentimento](#11-lgpd-cfm-consentimento)
12. [Custos por consulta](#12-custos-por-consulta)
13. [Riscos e mitigações](#13-riscos-e-mitigacoes)
14. [Decisões em aberto — perguntar antes de começar](#14-decisoes-em-aberto)
15. [Próximos passos](#15-proximos-passos)

---

## 1. Visão Executiva

A teleconsulta de Klivy hoje (Sprint K) permite que paciente e dentista entrem numa sala WebRTC, conversem em vídeo, e que o status do agendamento transicione automaticamente (`scheduled → confirmed → arrived → in_progress → completed`). Falta a camada de **persistência e análise**: gravar a consulta, transcrever, gerar uma proposta de evolução clínica via LLM, e oferecer ao dentista uma tela única pra revisar/aprovar tudo em um clique.

Este PRD define essa entrega, modelando 3 pipelines independentes (gravação → transcrição → evolução) orquestrados por jobs Sidekiq, mais uma nova aba no menu lateral consolidando histórico de teleconsultas.

**Objetivos de negócio:**
- Reduzir tempo de redação de evolução em ≥ 70% (de ~10min pra <3min de revisão)
- Criar histórico audiovisual auditável (compliance CFM)
- Diferenciar Klivy de Doctoralia/Doc24 que já cobram R$ 5–15 por consulta gravada
- Margem alvo: custo ~R$ 2,25/consulta de 1h, preço sugerido R$ 8–12

---

## 2. Problema e Oportunidade

**Problema atual (pós-Sprint K):**
- Dentista atende paciente, encerra a chamada e PRECISA redigir manualmente a evolução clínica enquanto a memória está fresca — caso contrário a qualidade do registro despenca.
- Não há registro audiovisual da consulta. Em disputas (paciente nega que foi orientado a tomar antibiótico, p.ex.) não há prova.
- Não há análise de "pontos de atenção" — dentista esquece de mencionar contraindicações, alergias do paciente.

**Oportunidade:**
- Pipeline assíncrono: ao fim da consulta, gravação é processada em background. Em 5–10min o dentista recebe transcrição + evolução pronta pra revisar.
- Diferencial competitivo claro: Doctoralia tem isso só no plano enterprise.
- Receita adicional: módulo cobrável por consulta gravada (margem ~80%).

---

## 3. Estado Atual

### Já implementado (Sprint K — fechado)

**Backend (`plugins/patient_portal/app/services/patient_portal/telemedicine/`):**
- `CredentialsResolver` — resolve credenciais LiveKit (account → ENV → dev defaults)
- `SessionIssuer` — emite JWT com identity `{role}-{id}-{nonce8hex}`, TTL 2h, retorna `room_code` (slug `pppp-eeee-aaaa`)
- `RoomCode` — gera e parseia slug estilo Google Meet
- `TelemedicineSession` — calcula janela (pre/post minutes), `permanently_blocked?`, `outside_window?`
- `StatusTransition` — state machine `scheduled → confirmed → arrived → in_progress → completed | no_show`
- `SessionTracker` — JSONB read/write em `custom_attributes.telemed_session`, lock + idempotência
- `SessionEventHandler` — orquestrador de `joined!`/`left!`
- Jobs: `MarkInProgressJob`, `MarkNoShowJob`

**Endpoints:**
- `POST /api/v1/patient_portal/appointments/:id/telemedicine_token` (paciente)
- `POST /api/v1/patient_portal/appointments/:id/telemedicine_event` (paciente — joined/left)
- `POST /api/v1/accounts/:id/agenda_events/:id/telemedicine_token` (doutor)
- `POST /api/v1/accounts/:id/agenda_events/:id/telemedicine_event` (doutor — joined/left)

**Frontend:**
- `TelemedicineRoom.vue` — componente puro da sala (header light, chat sidebar, tiles per-participant, avatar, active speaker border, preflight Meet-style com seleção de mic/cam + qualidade)
- `TelemedicineRoomPage` (paciente) e `AgendaTelemedRoomPage` (doutor) — wrappers
- `useTelemedicineSession` — composable de idempotência joined/left

**Infraestrutura local:**
- Procfile.dev sobe `backend`, `vite`, `livekit-server --dev`
- LiveKit usa `devkey`/`secret`, escuta em `ws://localhost:7880`

**Specs:** 75 examples passando (StatusTransition + SessionTracker + Handler + Jobs + RoomCode + SessionIssuer)

### Disponível no projeto mas ainda não usado pra teleconsulta

- **Cloudflare R2** via ActiveStorage (config em `config/storage.yml`, ENV vars `STORAGE_*`). Já em uso pelos exames médicos (`plugins/patients/app/models/exam_media.rb`).
- **OpenAI** via `ruby-openai` gem + `lib/captain/*` services. Default `gpt-4.1-mini`. Chaves no `InstallationConfig`.
- **Anthropic** suportado via `ruby_llm` (mapeado em `lib/llm_constants.rb`), sem uso ativo.
- **Sidekiq** rodando, jobs `patient_portal/telemedicine/*` já no padrão.

### Falta instalar/configurar

- **LiveKit Egress** — servidor separado (Docker) que faz gravação real. Open source, configura output pra S3-compatible (R2).
- **OpenAI Whisper** — chave provavelmente já válida (mesma conta), só ativar billing pro endpoint Whisper.
- **Gemini API key** — se decidirmos usar Gemini 2.5 Flash para audio nativo (ver §5).

---

## 4. Arquitetura Proposta

```
                      ┌──────────────────────────────────────┐
                      │   Sala (LiveKit room, Sprint K)     │
                      │   Doutor + Paciente conversam        │
                      └───────────────┬──────────────────────┘
                                      │ ambos conectados
                                      ▼
              ┌──────────────────────────────────────────────┐
              │  RecordingOrchestrator (NEW)                 │
              │  - dispara TrackEgressRequest no LiveKit     │
              │  - guarda recording_id no AgendaEvent JSONB  │
              └───────────────┬──────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────────────────────┐
              │  LiveKit Egress server (Docker container)    │
              │  - grava 2 arquivos: doctor.ogg + patient.ogg│
              │  - upload direto S3-compatible (R2)          │
              │  - webhook /livekit/egress/finished          │
              └───────────────┬──────────────────────────────┘
                              │ webhook
                              ▼
              ┌──────────────────────────────────────────────┐
              │  RecordingFinishedController (NEW)           │
              │  - valida HMAC                               │
              │  - cria TelemedRecording (model novo)        │
              │  - enfileira TranscribeRecordingJob          │
              └───────────────┬──────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────────────────────┐
              │  TranscribeRecordingJob (Sidekiq)            │
              │  - baixa doctor.ogg + patient.ogg do R2      │
              │  - chama provider de transcrição            │
              │  - mescla por timestamp:                     │
              │    [00:00:14] [Doutor] Bom dia...           │
              │    [00:00:17] [Paciente] Bom dia, doutor   │
              │  - persiste transcript em TelemedRecording   │
              │  - enfileira GenerateEvolutionJob            │
              └───────────────┬──────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────────────────────┐
              │  GenerateEvolutionJob (Sidekiq)              │
              │  - prompt: transcrição + ficha do paciente   │
              │  - chama Claude/GPT/Gemini                   │
              │  - parseia output em estrutura SOAP          │
              │  - persiste em ProposedEvolution (novo)      │
              │  - notifica dentista (push/email/in-app)     │
              └───────────────┬──────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────────────────────┐
              │  Tela "Teleconsulta" (menu lateral, NEW)    │
              │  - Lista de teleconsultas                   │
              │  - Player de vídeo (signed URL do R2)        │
              │  - Transcrição com timeline                  │
              │  - Evolução proposta (editor)               │
              │  - [Aprovar e publicar] → cria ClinicalNote  │
              └──────────────────────────────────────────────┘
```

### Princípios de design

- **Pipelines desacoplados** — cada job sabe fazer apenas uma coisa (gravar, transcrever, evoluir). Falha de um não derruba os outros. Retry isolado.
- **Storage como contrato** — arquivos no R2 são a fonte da verdade. Job pode rodar de novo sem perda.
- **Provider-agnostic** — `TranscriptionProvider` e `EvolutionProvider` são interfaces; implementações concretas (Whisper / AssemblyAI / Deepgram para transcrição; Claude / GPT / Gemini para evolução) são intercambiáveis via config.
- **Reuso do que já existe** — `StatusTransition`, `SessionTracker`, `SessionIssuer` continuam intocados. Recording é uma camada paralela.

---

## 5. Comparativo de Providers

### 5.1 Gravação — LiveKit Egress modes

| Modo | Output | Pros | Cons |
|---|---|---|---|
| **Room Composite** | 1 MP4 split-screen estilo Meet | Player único, fácil reassistir | Diarização precisa de algoritmo extra |
| **Track Egress** ✅ recomendado | 1 arquivo por participante (separado) | **Diarização automática** (cada áudio é uma pessoa), bandwidth otimizado | Player precisa sincronizar 2 streams |
| **Track Composite** | mistura faixas específicas | uso raro | complexidade extra |

**Decisão:** **Track Egress** com **áudio + vídeo separados por participante**. O áudio do `patient-Y` e do `doctor-X` chegam isolados — diarização sai "de graça". Pra player único, gera-se composite pós-fato com ffmpeg.

LiveKit Egress aceita S3-compatible storage com `force_path_style: true` — funciona direto com R2.

### 5.2 Transcrição

| Provider | Custo/h | Diarização | Idioma PT-BR | Latência |
|---|---|---|---|---|
| **OpenAI Whisper API** | $0.36 (`$0.006/min`) | manual (precisa pre-process) | excelente | 1–2min |
| **Whisper + Track Egress** ✅ recomendado | $0.36 ($0.18 × 2 faixas) | **automática** (arquivo separado por pessoa) | excelente | 1–2min |
| AssemblyAI | $0.37 | nativa | bom | 3–5min |
| Deepgram Nova-2 | $0.43 | nativa, qualidade superior | bom (mas pior que Whisper em PT-BR) | 30s (streaming) |
| **Gemini 2.5 Flash audio nativo** | $0.10 (1h audio ≈ 5.4M tokens × $0.075/$0.30) | via prompt | bom | 30s–1min |

**Decisão recomendada para MVP:** **Whisper + Track Egress**. Conta OpenAI já está configurada. Diarização sai natural porque os arquivos já vêm separados.

**Alternativa interessante:** Gemini 2.5 Flash. Suporta áudio nativo (não precisa transcrever separado) e pode rodar transcrição + análise + evolução em **1 chamada só**. Mais barato ($0.10 vs $0.36 + $0.06 = $0.42 do pipeline atual). Pode ser a opção de Fase 2 quando quisermos otimizar custos.

### 5.3 Evolução clínica (LLM)

Input: transcrição com tags `[Doutor]` / `[Paciente]` (~10k tokens pra 1h) + ficha do paciente (histórico, alergias, medicações).
Output: estrutura SOAP + pontos de atenção (~1.5k tokens).

| Modelo | $/1M input | $/1M output | Total/1h consulta | Pros | Cons |
|---|---|---|---|---|---|
| **Claude Sonnet 4.6** ✅ recomendado | $3 | $15 | **$0.06** | melhor escrita médica PT-BR, raciocínio | precisa configurar Anthropic provider |
| Claude Opus 4.7 | $15 | $75 | $0.30 | qualidade premium | 5× mais caro sem ganho mensurável aqui |
| GPT-4o | $2.50 | $10 | $0.045 | já configurado | escrita médica boa, não excelente |
| GPT-4.1-mini (atual padrão) | $0.40 | $1.60 | $0.007 | super barato | qualidade de evolução clínica fraca |
| **Gemini 2.5 Pro** | $1.25 | $10 | $0.025 | suporte audio nativo, contexto longo | qualidade médica PT-BR ainda não validada |
| Gemini 2.5 Flash | $0.30 | $2.50 | $0.007 | barato, audio nativo | qualidade variável |

**Decisão recomendada:** **Claude Sonnet 4.6** para a evolução. A diferença em reais ($0.06 vs $0.007 do mini) é irrelevante na soma, mas a diferença em qualidade de escrita médica em PT-BR é grande. Para clínica é onde NÃO economizar.

**Alternativa: Gemini 2.5 Pro com audio nativo.** Se quisermos uma stack unificada (1 chamada faz transcrição + evolução), Gemini pode ser experimentado em paralelo (A/B) e adotado se a qualidade clínica em PT-BR for comparável.

### 5.4 Storage (R2 vs S3 vs B2)

**Decisão:** **R2** (já em uso no projeto pra exames).
- Storage: $0.015/GB/mês
- Egress: **zero** (vantagem chave do R2 — playback do dentista não cobra banda)
- Bucket separado: `klivy-telemed-recordings` (retention policy diferente dos exames)

---

## 6. Nova Aba "Teleconsulta" no menu lateral

Localização no menu lateral atual: `BIA · Agenda · Pacientes · Financeiro · Contatos · ...`
Adicionar: **`Teleconsulta`** entre Agenda e Pacientes.

### 6.1 Estrutura de telas

```
Teleconsulta (rota: /accounts/:account_id/teleconsultas)
├─ Tab "Próximas"     — teleconsultas agendadas (status scheduled/confirmed)
├─ Tab "Em andamento" — status arrived/in_progress (chip vermelho pulsante)
├─ Tab "Finalizadas"  — completed (com gravação disponível)
└─ Tab "Sem comparec." — no_show

Cada linha mostra:
  [paciente] [horário] [duração] [status] [evolução: pendente/aprovada/N/A]
  ações: [Entrar na sala] (se em andamento) · [Ver detalhes]
```

### 6.2 Tela de detalhes da teleconsulta finalizada

```
┌────────────────────────────────────────────────────────────────────────┐
│ Paciente: João Silva                            Status: ✅ Finalizada  │
│ 20/05/2026 15:00 → 15:48 · Dr. Maria (Ortodontia)                     │
│ Código da sala: 0017-0185-0001                                         │
├────────────────────────────────────────────────────────────────────────┤
│  [▶ Player de vídeo (mosaico doutor + paciente sincronizado)]         │
├──────────────────────┬─────────────────────────────────────────────────┤
│ Transcrição          │ Evolução proposta pela IA                       │
│                      │                                                  │
│ [00:00:14] Doutor:   │ S — Subjetivo                                   │
│ Bom dia, João, como  │ Paciente relata sensibilidade em dente 36 há   │
│ você está hoje?      │ 2 semanas, agravada com líquidos frios.        │
│                      │                                                  │
│ [00:00:17] Paciente: │ O — Objetivo                                    │
│ Bom dia, doutor,     │ Exame visual indica desgaste cervical em 36.   │
│ tô com uma dor no    │ ⚠️ Atenção: paciente não mencionou se está    │
│ dente do fundo...    │ tomando medicação (verificar contraindicações).│
│                      │                                                  │
│ ...                  │ A — Avaliação                                   │
│                      │ Hipótese: hipersensibilidade dentinária.       │
│                      │                                                  │
│                      │ P — Plano                                       │
│                      │ Aplicação tópica de flúor + verniz             │
│                      │ dessensibilizante; reavaliar em 15 dias.       │
│                      │                                                  │
│                      │ [Editar] [✅ Aprovar e publicar evolução]      │
└──────────────────────┴─────────────────────────────────────────────────┘
```

### 6.3 Permissões

- **Lista da clínica inteira**: usuário com `beclinic_scope == 'all'` (admin)
- **Só minhas teleconsultas**: usuário com `scope == 'own'`
- **Ver gravação**: apenas o profissional responsável (`record.user_id == current_user.id`) — mesmo padrão do `telemedicine_join?`
- **Aprovar evolução**: idem (só o dentista que atendeu pode aprovar)

### 6.4 Componentes Vue novos

```
plugins/agenda/frontend/   ← reaproveita plugin agenda (telemed nasceu lá)
└─ features/teleconsulta/
   ├─ TeleconsultaListPage.vue          (lista com tabs + filtros)
   ├─ TeleconsultaDetailPage.vue        (player + transcrição + evolução)
   ├─ TeleconsultaRecordingPlayer.vue   (vídeo mosaico)
   ├─ TeleconsultaTranscript.vue        (lista com timestamps clicáveis)
   ├─ TeleconsultaEvolutionEditor.vue   (Markdown editor com seções SOAP)
   └─ useTeleconsultaList.js            (composable de filtros + paginação)
```

---

## 7. Modelo de Dados

### 7.1 Nova tabela `telemed_recordings`

```ruby
create_table :telemed_recordings do |t|
  t.references :agenda_event, null: false, foreign_key: true, index: true
  t.references :account,      null: false, foreign_key: true, index: true

  # LiveKit egress info
  t.string :egress_id, null: false, index: { unique: true }
  t.string :status, null: false, default: 'pending'
  # values: pending | recording | uploaded | transcribing | transcribed | evolving | ready | failed

  # Storage (R2)
  t.string :doctor_audio_key      # ex: 'recordings/2026/05/20/0017-0185-0001/doctor.opus'
  t.string :patient_audio_key
  t.string :doctor_video_key
  t.string :patient_video_key
  t.string :composite_video_key   # gerado pelo CompositeRecordingJob (opcional Fase 2)

  # Métricas
  t.integer :duration_seconds
  t.integer :total_size_bytes

  # Transcrição
  t.text :transcript_text         # com tags [Doutor]/[Paciente] e timestamps
  t.jsonb :transcript_segments    # [{start, end, speaker, text}, ...]
  t.string :transcript_provider   # 'whisper' | 'assemblyai' | 'deepgram' | 'gemini'

  # Falhas
  t.text :failure_reason
  t.integer :retry_count, default: 0

  t.timestamps
end
```

### 7.2 Nova tabela `proposed_evolutions`

Separada de `telemed_recordings` pra permitir reprocessamento (gerar nova proposta sem refazer gravação/transcrição).

```ruby
create_table :proposed_evolutions do |t|
  t.references :telemed_recording, null: false, foreign_key: true, index: true
  t.references :clinical_note, foreign_key: true, index: true  # nil até aprovação

  t.string  :provider, null: false     # 'claude-sonnet-4.6', 'gpt-4o', 'gemini-2.5-pro'
  t.jsonb   :soap_structure            # {subjetivo, objetivo, avaliacao, plano}
  t.text    :raw_markdown              # markdown completo
  t.jsonb   :attention_points          # [{type, severity, text}, ...]

  t.string  :status, null: false, default: 'pending_review'
  # values: pending_review | edited | approved | rejected

  t.references :reviewed_by, foreign_key: { to_table: :users }
  t.datetime :reviewed_at

  t.integer :input_tokens
  t.integer :output_tokens

  t.timestamps
end
```

### 7.3 Colunas adicionais em `agenda_events`

Nenhuma. O JSONB `custom_attributes.telemed_session` (Sprint K) continua sendo o estado de quem-está-na-sala. Recording vive em sua própria tabela com FK pra agenda_event.

### 7.4 Colunas adicionais em `clinical_notes`

```ruby
add_reference :clinical_notes, :proposed_evolution, foreign_key: true, index: true
add_column :clinical_notes, :source, :string, default: 'manual'
# values: 'manual' | 'telemed_ai'
```

Permite identificar evoluções nascidas de IA pra auditoria/CFM.

### 7.5 Coluna em `patient_portal_settings`

```ruby
add_column :patient_portal_settings, :telemedicine_recording, :jsonb, default: {}
# Estrutura:
# {
#   "enabled": true,
#   "auto_start": true,           # gravar automaticamente quando ambos entram
#   "patient_consent_required": true,
#   "retention_days": 7300        # 20 anos por CFM
# }
```

---

## 8. APIs novas

### 8.1 Backend

```
# Webhook do LiveKit Egress — pode vir de IP público, validar HMAC
POST   /webhooks/livekit/egress
        body: { event_id, egress_id, status, files: [...] }
        signed via Authorization header (LiveKit assina)

# Listagem
GET    /api/v1/accounts/:id/teleconsultas
        ?tab=upcoming|in_progress|finished|no_show
        ?page=1&per_page=20
        ?professional_id=X
        ?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD

# Detalhe
GET    /api/v1/accounts/:id/teleconsultas/:event_id

# Signed URL pra player
GET    /api/v1/accounts/:id/teleconsultas/:event_id/recording_url
        ?kind=doctor_video|patient_video|composite|doctor_audio|patient_audio
        retorna URL temporária (5min) do R2

# Reprocessar (admin only — debug)
POST   /api/v1/accounts/:id/teleconsultas/:event_id/retranscribe
POST   /api/v1/accounts/:id/teleconsultas/:event_id/reevolve

# Aprovar / editar evolução
PATCH  /api/v1/accounts/:id/proposed_evolutions/:id
        body: { soap_structure: {...}, raw_markdown: "..." }
POST   /api/v1/accounts/:id/proposed_evolutions/:id/approve
        cria ClinicalNote com source='telemed_ai'
POST   /api/v1/accounts/:id/proposed_evolutions/:id/reject
        body: { reason: "..." }
```

### 8.2 Frontend (Vuex actions)

```
teleconsultas/fetchList({ tab, filters })
teleconsultas/fetchDetail(eventId)
teleconsultas/fetchRecordingUrl({ eventId, kind })
proposedEvolutions/update({ id, payload })
proposedEvolutions/approve(id)
proposedEvolutions/reject({ id, reason })
```

---

## 9. Pipeline Completo

### 9.1 Sequência de eventos (happy path)

```
[T=0]     Paciente entra na sala
          → SessionEventHandler::joined!(patient)
          → status: confirmed → arrived

[T=0:30]  Doutor entra
          → SessionEventHandler::joined!(doctor)
          → enfileira MarkInProgressJob(5min)

[T=0:30]  RecordingOrchestrator (novo) detecta both_present:
          → cria TelemedRecording(status='pending')
          → POST LiveKit Egress API:
             { room_name, layout: 'track', audio_only: false,
               s3: { bucket: 'klivy-telemed-recordings', endpoint, ... } }
          → grava egress_id na TelemedRecording

[T=0:30 → T=48:00]  LiveKit Egress grava em background.
                     Cada participant escreve em arquivos separados:
                     - recordings/2026/05/20/0017-0185-0001/doctor-{nonce}.opus
                     - recordings/2026/05/20/0017-0185-0001/patient-{nonce}.opus
                     - (e .mp4 se vídeo ativo)

[T=5:30]  MarkInProgressJob roda → status: arrived → in_progress

[T=48:00] Doutor + paciente saem (ambos clicam Sair).
          → SessionEventHandler::left!() pra cada
          → status: in_progress → completed
          → RecordingOrchestrator::stop() chama LiveKit Egress API para
            finalizar gravação.

[T=48:30] LiveKit Egress finaliza upload do R2 → dispara webhook:
          POST /webhooks/livekit/egress
          { egress_id, status: 'complete', files: [
            { type: 'audio_track', participant: 'doctor-...', key: '...opus' },
            ...
          ] }
          → controller valida HMAC, atualiza TelemedRecording(status='uploaded')
          → enfileira TranscribeRecordingJob(recording.id)

[T=49:00] TranscribeRecordingJob:
          - baixa doctor.opus + patient.opus do R2
          - chama Whisper API pra cada (paralelo)
          - mescla por timestamp em transcript_segments
          - persiste em TelemedRecording.transcript_text + transcript_segments
          - status: transcribing → transcribed
          - enfileira GenerateEvolutionJob(recording.id)

[T=50:30] GenerateEvolutionJob:
          - lê transcript + ficha do paciente (alergias, histórico)
          - monta prompt SOAP estruturado
          - chama Claude Sonnet 4.6 via ruby_llm
          - parseia output em SOAP + attention_points
          - cria ProposedEvolution(status='pending_review')
          - status do recording: evolving → ready
          - notifica dentista via web push: "Evolução de João Silva pronta"

[T=51:00] Dentista abre aba Teleconsulta → Finalizadas → João Silva
          → vê player, transcrição, evolução proposta
          → edita 2 linhas → clica "Aprovar e publicar"
          → cria ClinicalNote(source='telemed_ai', proposed_evolution_id=...)
          → evolução aparece no prontuário do paciente.
```

### 9.2 Cenários de falha

| Falha | Detecção | Recuperação |
|---|---|---|
| Egress não inicia | LiveKit API retorna erro | Logar, status='failed', notificar admin. Continuar consulta sem gravação. |
| Egress travou no meio | Sem webhook após N min | Job `ReapStaleRecordingsJob` (a cada 1h) cancela e marca failed. |
| Whisper falha | API 5xx | Sidekiq retry 3× com backoff exponencial. Após 3 falhas, status='failed'. |
| LLM gerou JSON malformado | Parser não consegue extrair SOAP | Salva raw_markdown e marca attention "AI output não estruturado". |
| Paciente saiu, doutor não | left! só pra paciente. SessionTracker mostra doctor_present=true. | Recording continua. Quando doutor sai, encerra normalmente. |
| Doutor saiu, paciente não | Idem (espelhado) | Idem. |
| Disconnect repentino de ambos | `RoomEvent.Disconnected` → emitSessionLeft chamado em ambos | Webhook do Egress dispara igual. |

---

## 10. Fases de entrega

### MVP — Sprint L (estimativa: 6–9 dias)

Entrega o fluxo end-to-end SEM otimizações de player.

**Backend:**
- [ ] Instalar `livekit-egress` no Procfile.dev (Docker container local)
- [ ] Migration `telemed_recordings` + `proposed_evolutions` + colunas em clinical_notes
- [ ] `PatientPortal::Telemedicine::RecordingOrchestrator` — `start!` e `stop!`
- [ ] `Webhooks::Livekit::EgressController` — validar HMAC, persistir, enfileirar
- [ ] `TranscribeRecordingJob` — Whisper (2 faixas → merge)
- [ ] `GenerateEvolutionJob` — Claude Sonnet 4.6 via ruby_llm
- [ ] `Teleconsultas::ListingController` + `DetailController` + `RecordingUrlController`
- [ ] `Teleconsultas::ProposedEvolutionsController` — update/approve/reject
- [ ] Pundit policies pra todas as ações novas
- [ ] Specs de todos os jobs + controllers + policies (~30 examples novos)

**Frontend:**
- [ ] Nova entrada no menu lateral (`Teleconsulta`) com badge de pendentes
- [ ] `TeleconsultaListPage` com tabs e filtros
- [ ] `TeleconsultaDetailPage` com player + transcrição + editor
- [ ] `TeleconsultaEvolutionEditor` (Markdown WYSIWYG)
- [ ] Composable `useTeleconsultaList`
- [ ] Integração com store Vuex
- [ ] Testes e2e (Cypress) do fluxo crítico

**Infraestrutura:**
- [ ] Bucket R2 `klivy-telemed-recordings` provisionado
- [ ] ENV vars: `LIVEKIT_EGRESS_URL`, `LIVEKIT_EGRESS_API_KEY`, `LIVEKIT_EGRESS_API_SECRET`, `OPENAI_WHISPER_KEY`, `ANTHROPIC_API_KEY`
- [ ] Docker container `livekit/egress` no Procfile.dev + docker-compose.prod.yml

**Funcional do MVP:**
- ✅ Grava (vídeo + áudio separados por participante)
- ✅ Transcreve (Whisper + merge por timestamp)
- ✅ Gera evolução proposta (Claude Sonnet 4.6)
- ✅ Nova aba "Teleconsulta" com lista + detalhes
- ✅ Player simples (2 vídeos lado-a-lado, sem composite)
- ✅ Editor da evolução + aprovação cria ClinicalNote
- ✅ Consent básico do paciente no preflight (checkbox)

### Fase 2 — pós-MVP (4–6 dias)

- [ ] **Composite video** — job que gera 1 MP4 split-screen com ffmpeg pós-gravação. Player único.
- [ ] **Streaming live transcription** — Deepgram websocket exibe legendas durante a chamada (sem persistir).
- [ ] **Notificações push** quando evolução fica pronta
- [ ] **Reprocessar** evolução com modelo diferente (botão "Tentar com Gemini" / "Tentar com Opus")
- [ ] **Pontos de atenção destacados** no editor (highlights amarelos com tooltip)
- [ ] **Histórico do paciente** no prompt — passar últimas 3 consultas como contexto
- [ ] **Compressão de vídeo** — ffmpeg pós-processa pra reduzir 700MB → 400MB
- [ ] **Player com playback x1.5 / x2** + busca por keyword na transcrição (clica frase → vídeo pula)

### Fase 3 — diferenciação

- [ ] **Gemini 2.5 Pro audio nativo** — 1 chamada faz transcrição + evolução. A/B com pipeline atual.
- [ ] **Análise de risco clínico** — LLM compara evolução com histórico e sinaliza divergências graves
- [ ] **Resumo executivo de paciente** — pra primeira consulta, LLM gera "perfil" baseado em todas teleconsultas anteriores
- [ ] **Exportação pra Doctoralia / outros sistemas** — formato HL7 FHIR
- [ ] **Dashboard de qualidade** — % de evoluções aprovadas sem edição (proxy de qualidade do LLM)

---

## 11. LGPD / CFM / Consentimento

**CRÍTICO — sem isso, NÃO ligar gravação em produção.**

### Requisitos legais

- **LGPD Art. 7º** — consentimento explícito do paciente pra tratar dados sensíveis de saúde, incluindo voz/vídeo.
- **CFM 2.314/2022** — telemedicina exige registro auditável. Recomenda retenção mínima de 20 anos no prontuário.
- **CFM 1.821/2007** — prontuário digital deve ter assinatura digital (futuro: integração com certificado A3/A1 do dentista).

### O que precisamos implementar

**No preflight (antes de entrar na sala):**

```
☑ Aceito que esta consulta seja gravada para fins de prontuário e
   compliance, conforme termos LGPD e CFM 2.314/2022.

[Conferir termos completos] [Cancelar consulta] [Aceitar e entrar]
```

- Persistir em `consent_records` (tabela já existe no projeto pra outros consents).
- Sem checkbox marcado → conexão na sala segue normal MAS Egress NÃO inicia.
- Dentista vê chip "⚠️ Não gravado — paciente não consentiu" na lista de teleconsultas.

**Na sala ao vivo:**

- Chip vermelho permanente no canto: `🔴 Gravando — Sprint K + L`
- Ícone de microfone vermelho/pulsante quando ativo.
- Paciente pode parar a gravação a qualquer momento (botão "Parar gravação"). Gravação parcial é retida.

**Configurações da clínica:**

```
patient_portal_settings.telemedicine_recording = {
  enabled: true|false,
  auto_start: true,                    # gravar sem pedir confirmação
  patient_consent_required: true,      # bloquear se paciente não consentir
  retention_days: 7300,                # 20 anos
  delete_unconsented: true,            # se consent vencer, deletar arquivos
  ai_evolution_enabled: true,          # opt-in da clínica pro LLM
  ai_provider: 'claude-sonnet-4.6'
}
```

### Validação jurídica

**Antes de produção**, validar com jurídico:
- Texto exato do consent
- Período de retenção (sugestão CFM = 20 anos; mas alguns estados pedem 25)
- Direito de exclusão sob solicitação (LGPD Art. 18) — implementar `DeletePatientRecordingsJob`
- Onde os arquivos podem ser armazenados (R2 EU/US — pra LGPD, **garantir bucket R2 região São Paulo**)

---

## 12. Custos por consulta

### Por consulta de 1h (Track Egress, Whisper, Claude Sonnet 4.6)

| Componente | Custo USD | Custo R$ |
|---|---|---|
| Storage R2 (700 MB × 1 mês) | $0.01 | R$ 0,05 |
| Egress container (5min CPU compute) | $0.01 | R$ 0,05 |
| Whisper × 2 faixas (1h cada × $0.36) | $0.36 | R$ 1,85 |
| Claude Sonnet 4.6 (10k in + 1.5k out) | $0.06 | R$ 0,30 |
| **Total/consulta** | **$0.44** | **~R$ 2,25** |

### Variantes

| Stack | Custo/1h | Quando usar |
|---|---|---|
| Whisper + Sonnet 4.6 ✅ MVP | $0.44 | qualidade clínica primeiro |
| Gemini 2.5 Flash audio (1 chamada) | $0.10 | escala alta, custo crítico |
| Gemini 2.5 Pro audio (1 chamada) | $0.30 | escala alta + qualidade |
| Whisper + GPT-4o | $0.40 | similar ao MVP |
| Whisper + Opus 4.7 | $0.69 | casos críticos (segunda opinião) |

### Mensal (clínica média, 200 consultas/mês)

- Variável: 200 × R$ 2,25 = **R$ 450/mês**
- Storage acumulado (20 anos retenção): cresce ~140 GB/mês, ~$2/mês adicional cada mês
- Egress server (compute idle entre consultas): ~$25–50/mês (1 VPS dedicado pequeno)

### Preço sugerido pro cliente

- R$ 8–12 por consulta gravada → margem 75–80%
- Ou pacote: R$ 1.500–2.500/mês "Plano Teleconsulta Premium" pra clínica com até 200 consultas

---

## 13. Riscos e mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| **LiveKit Egress instável em prod** | média | alto (perde gravações) | Job `ReapStaleRecordingsJob`, monitoramento Sentry, retry com idempotência |
| **Whisper retorna texto sem sentido em PT-BR clínico** | baixa | médio | A/B com Gemini Flash em paralelo na Fase 2 |
| **LLM "alucina" evolução** | média | **CRÍTICO** | dentista SEMPRE revisa antes de aprovar; nunca auto-publica; prompts incluem "se incerto, deixe em branco" |
| **Paciente nega consent depois da consulta** | baixa | médio | botão "Excluir minha gravação" no portal; job de delete |
| **Custo OpenAI inesperado** | baixa | médio | rate limiter no Sidekiq (max 10 transcrições/min); alerta em $X/dia |
| **Storage R2 acumula sem limite** | alta (longo prazo) | médio | retention policy 20 anos com `DeleteExpiredRecordingsJob` (Sidekiq cron) |
| **Concorrência de Egress por sala** | baixa | baixo | idempotência via `egress_id` único; orchestrator só dispara se não houver pending/recording |
| **Latência de evolução > 10min** | baixa | médio | mostrar progresso ("Transcrevendo... 30%") na aba Teleconsulta |

---

## 14. Decisões em aberto — perguntar antes de começar

> **Importante:** levar essas perguntas pra próxima sessão antes de codar.

1. **Provider de evolução** — Claude Sonnet 4.6 (recomendado) ou começar com GPT-4o (já configurado)?
2. **Bucket R2 — região São Paulo** disponível? Se não, qual é a aceitável pra LGPD?
3. **Composite video no MVP** ou só 2 streams lado-a-lado (decisão UX)?
4. **Consent UI** — checkbox simples no preflight ou tela cheia obrigatória estilo termo médico assinado?
5. **Notificação ao dentista** — push, email, in-app, ou tudo?
6. **Pode editar transcrição** ou só a evolução? (sugestão: editar evolução; transcrição é read-only por compliance)
7. **Quem paga a gravação** — clínica (incluído no plano) ou paciente (consulta gravada custa mais)? — afeta UX do preflight
8. **Retenção: 20 anos é firm?** Algumas clínicas pedem 5 anos por custo. Tornar configurável?
9. **Streaming live transcription** entra no MVP ou Fase 2? Custa mais ($1–2/h Deepgram), mas é uau-factor pro dentista ver legendas durante a consulta
10. **Quando começar Egress** — automático quando ambos entram, ou botão manual "Iniciar gravação" pro dentista?

---

## 15. Próximos passos

### Imediato (antes de codar)

1. **Validar §14** com stakeholder (Leandro) numa sessão de 30min
2. **Confirmar conta Anthropic** + setar `ANTHROPIC_API_KEY` no `InstallationConfig`
3. **Provisionar bucket R2** `klivy-telemed-recordings` (região, ACL, retention)
4. **Validar texto de consent** com jurídico (ou usar template provisório com disclaimer "MVP")

### Sprint L (após validação)

Ordem de implementação sugerida (cada item ~0.5–1 dia):

1. Migrations + models (`TelemedRecording`, `ProposedEvolution`)
2. `RecordingOrchestrator` + spec
3. Subir `livekit-egress` Docker local + smoke test
4. `Webhooks::Livekit::EgressController` + spec (HMAC validation)
5. `TranscribeRecordingJob` + spec (mock Whisper)
6. `GenerateEvolutionJob` + spec (mock LLM)
7. Endpoints REST (listagem, detalhe, recording_url, evolution CRUD) + specs
8. Pundit policies + specs
9. **Frontend**: nova rota + entrada no menu + `TeleconsultaListPage`
10. **Frontend**: `TeleconsultaDetailPage` + player + transcript viewer
11. **Frontend**: `TeleconsultaEvolutionEditor` + fluxo de aprovação
12. **Consent**: checkbox no preflight + persistência em consent_records
13. E2E test (Cypress) do fluxo completo

### Após MVP

Validar com 1 clínica piloto → coletar feedback → iniciar Fase 2 priorizando o que mais doeu.

---

## Anexo A — Stack tecnológico consolidado

| Camada | Tecnologia | Estado |
|---|---|---|
| WebRTC | LiveKit (server + Egress) | server ok, Egress falta |
| Storage | Cloudflare R2 | configurado, falta bucket |
| Transcrição | OpenAI Whisper | falta ativar billing |
| LLM evolução | Claude Sonnet 4.6 (via ruby_llm) | gem instalada, falta key |
| Backend | Rails 7.1 + Sidekiq | em uso |
| Frontend | Vue 3 + Pinia + Vue Router | em uso |
| Auth | Devise (Chatwoot) + JWT portal | em uso |
| Database | PostgreSQL 14+ | em uso |
| Queue | Sidekiq + Redis | em uso |
| Monitoramento | Sentry (recomendado) | a configurar |

## Anexo B — Referências externas

- LiveKit Egress: https://docs.livekit.io/home/egress/outputs/
- LiveKit Egress GitHub: https://github.com/livekit/egress
- OpenAI Whisper API: https://platform.openai.com/docs/guides/speech-to-text
- Anthropic Claude (ruby_llm já instalada): https://docs.anthropic.com/
- Gemini 2.5 audio: https://ai.google.dev/gemini-api/docs/models#gemini-2.5-flash
- CFM 2.314/2022 (telemedicina): https://portal.cfm.org.br/
- LGPD Lei 13.709/2018 (dados sensíveis): http://www.planalto.gov.br/

---

**Fim do PRD.** Próxima sessão: revisar §14, validar com stakeholder, iniciar Sprint L.
