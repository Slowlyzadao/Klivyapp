# Telemedicina (Klivy) — Documentação Técnica

> **Audiência**: programador que vai replicar o plugin de teleconsulta em outro sistema (ou auditá-lo). Não é guia de uso pro usuário final.
>
> **Última atualização**: 2026-05-26.

---

## 1. O que isto cobre

Tudo que foi construído pra a feature de **Teleconsulta** (telemedicina por vídeo + IA clínica) dentro da plataforma Klivy:

- Sala de vídeo WebRTC (LiveKit) com waiting room, gravação e blur de fundo.
- Gravação por participante (egress) + composite, armazenada em Cloudflare R2.
- Transcrição com diarização (OpenAI `gpt-4o-transcribe-diarize`).
- Geração automática de evolução clínica (Anthropic Claude `claude-sonnet-4-6`) com formato "Registro de Procedimento" (14 campos editáveis).
- Trilha de aprovação humana antes de virar prontuário (`SessionLog`).
- Consentimento LGPD do paciente, encryption em colunas sensíveis, audit trail completa.

A arquitetura está isolada em um **Rails Engine + Vue plugin** em [`plugins/telemed/`](../../plugins/telemed/), com pontos de extensão minimamente invasivos no core (apenas `has_many` injetados nos models `Account`, `Patient`, `AgendaEvent`).

---

## 2. Índice da documentação

| Doc | Pra quê | Quem lê |
|-----|---------|---------|
| [01-arquitetura.md](01-arquitetura.md) | Visão macro: como o plugin se encaixa no core, decisões de design, camadas. | Antes de qualquer outra coisa. |
| [02-stack-dependencias.md](02-stack-dependencias.md) | Todas as gems Ruby, pacotes NPM, ENV vars, serviços externos (LiveKit, R2, Anthropic, OpenAI). | DevOps / setup inicial. |
| [03-modelo-dados.md](03-modelo-dados.md) | Schema PostgreSQL, migrations, indexes, encryption (LGPD), associações. | Quem for replicar tabelas. |
| [04-backend.md](04-backend.md) | Controllers, services, jobs, webhook LiveKit, orquestração da gravação. | Backend dev. |
| [05-frontend.md](05-frontend.md) | Componentes Vue (sala, dashboard, paciente), LiveKit SDK, composables. | Frontend dev. |
| [06-apis-endpoints.md](06-apis-endpoints.md) | Lista exaustiva de endpoints HTTP + payloads de exemplo. | Quem precisa integrar / testar. |
| [07-fluxos-end-to-end.md](07-fluxos-end-to-end.md) | Sequências completas (consulta criada → vídeo → gravação → transcrição → evolução → prontuário). | Pra entender o todo. |
| [08-prompts-ia.md](08-prompts-ia.md) | Prompt completo do Claude, parser, mapeamento `procedure_fields`. | Quem for ajustar IA. |
| [09-replicacao-checklist.md](09-replicacao-checklist.md) | Passo a passo pra replicar do zero em outro sistema. | TL;DR pro programador. |

---

## 3. Mapa-relâmpago da arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                          BROWSER (Vue 3)                         │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐   │
│  │ Dashboard      │  │ Patient Portal │  │ TelemedicineRoom │   │
│  │ (clínica)      │  │ (paciente)     │  │ (compartilhado)  │   │
│  │                │  │                │  │  livekit-client  │   │
│  └────────┬───────┘  └────────┬───────┘  └────────┬─────────┘   │
└───────────┼──────────────────┼──────────────────┼───────────────┘
            │                  │                  │ WebRTC
            │ HTTP (axios)     │ HTTP             │ (UDP/TURN)
            ▼                  ▼                  ▼
┌─────────────────────────────────────────┐ ┌────────────────────┐
│   Rails 7.1 (Klivy core + plugins)      │ │   LiveKit Server   │
│                                          │ │  (self-host / Cloud)│
│  ┌────────────────────────────────────┐ │ │                    │
│  │ plugins/telemed/                   │ │ │  - Rooms           │
│  │  ├ Controllers (4)                 │ │ │  - Egress (3 jobs) │
│  │  ├ Services (~12)                  │ │ │  - JWT tokens      │
│  │  ├ Jobs (Sidekiq, 5)               │ │ │  - Webhooks        │
│  │  └ Models (3: Recording,           │ │ │                    │
│  │      ProposedEvolution, Consent)   │ │ └─────────┬──────────┘
│  └────────────────────────────────────┘ │           │
│                                          │           │ Egress
│  ┌────────────────────────────────────┐ │           │ webhook
│  │ Core models referenciados:         │ │           ▼
│  │  - Account, Patient, AgendaEvent   │ │  ┌────────────────┐
│  │  - SessionLog (prontuário novo)    │ │  │ Cloudflare R2  │
│  │  - PatientPortalSetting (config IA)│ │  │ (audio storage)│
│  └────────────────────────────────────┘ │  └────────┬───────┘
└─────────────────────────────────────────┘           │
            │                                          │ download
            ▼                                          ▼
┌──────────────────┐     ┌─────────────────────────────────────┐
│  PostgreSQL      │     │  Sidekiq jobs (workers)             │
│  (Klivy DB)      │     │   - TranscribeRecordingJob          │
│  ActiveRecord    │     │      → OpenAI gpt-4o-transcribe     │
│  encryption em   │     │   - GenerateEvolutionJob            │
│  campos PII      │     │      → Anthropic Claude (ruby_llm)  │
└──────────────────┘     │   - MarkNoShowJob, MarkInProgressJob│
                          │   - EnforceRecordingQuotaJob        │
                          └─────────────────────────────────────┘
```

---

## 4. Quick start (replicação)

Sequência sugerida pra um programador entender e replicar:

1. **Leia [01-arquitetura.md](01-arquitetura.md)** para mapa mental.
2. **Provisione serviços externos** seguindo [02-stack-dependencias.md](02-stack-dependencias.md):
   - LiveKit (self-host docker ou Cloud)
   - Cloudflare R2 bucket
   - Anthropic API key
   - OpenAI API key
3. **Crie as migrations** ([03-modelo-dados.md](03-modelo-dados.md)).
4. **Copie e adapte** o backend ([04-backend.md](04-backend.md)) — controllers, services, jobs.
5. **Copie e adapte** o frontend ([05-frontend.md](05-frontend.md)) — componentes Vue, LiveKit SDK.
6. **Configure o prompt da IA** ([08-prompts-ia.md](08-prompts-ia.md)).
7. **Teste end-to-end** seguindo [07-fluxos-end-to-end.md](07-fluxos-end-to-end.md).

---

## 5. Convenções de notação usadas nos docs

- **Paths absolutos** referenciam o repo Klivy a partir da raiz: `plugins/telemed/...`.
- **Endpoints HTTP** seguem convenção Rails-RESTful: `GET /api/v1/accounts/:account_id/...`.
- **ENV vars** estão em CAPS_SNAKE: `LIVEKIT_API_KEY`, `ANTHROPIC_API_KEY`.
- **Modelos**: `PascalCase` (`TelemedRecording`); colunas: `snake_case` (`storage_key`).
- **Estados de máquina** (status enum): em strings minúsculas (`pending`, `recording`, `ready`).

---

## 6. Auditoria histórica

Documento `TELEMED_AUDIT_2026-05-25.md` na raiz do repo tem o registro completo de bugs/correções/decisões durante a auditoria do plugin. Estes docs aqui são o **estado atual após auditoria** — para entender *por que* algumas decisões foram tomadas, vale ler o audit em paralelo.
