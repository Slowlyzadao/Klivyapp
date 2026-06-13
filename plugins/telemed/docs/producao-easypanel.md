# Telemed em produção (EasyPanel) — o que precisa pra funcionar

Guia prático do que configurar pra a **Teleconsulta** rodar em produção. O
código já vai na imagem Docker (`mamedes/klivy-prod`); o que falta é
**variáveis de ambiente + serviços externos + config da clínica**.

> Dev local é outra coisa (LiveKit no `docker-compose.override.yml`, MinIO,
> `host.docker.internal`). **Nada disso vai pra prod.** Em prod use LiveKit
> Cloud (ou self-host com TURN + domínio) e R2 real.

---

## 0. Por camada — o mínimo de cada tier

A teleconsulta funciona em camadas. Você só precisa configurar até onde quer ir:

| Tier | O que faz | Precisa de |
|---|---|---|
| **1. Vídeo** | doutor + paciente na sala, admitir | LiveKit (Cloud) |
| **2. Gravação** | grava o áudio da consulta | + LiveKit Egress + bucket R2 + webhook |
| **3. Transcrição** | vira texto (Whisper) | + chave OpenAI |
| **4. Evolução IA** | gera o SOAP/registro (Claude) | + chave Anthropic |

Em **todos** os tiers, em produção, são **obrigatórias as 3 chaves de
criptografia** (senão o app nem sobe — ver §2).

---

## 1. Serviços externos a provisionar

1. **LiveKit** — **LiveKit Cloud** (recomendado; free tier serve pra começar).
   Dá uma URL `wss://` pública (funciona pro browser e pro backend), **TURN
   gerenciado** (sem TURN, paciente em 4G/celular não conecta) e **Egress**
   pra gravação. Alternativa: self-host com `coturn` + domínio + TLS.
2. **Cloudflare R2** — bucket pras gravações. Pode reusar o R2 do ActiveStorage
   ou criar um dedicado (`klivy-telemed-recordings`, retenção CFM 20 anos
   separada). Região São Paulo se possível (LGPD).
3. **OpenAI** — chave com billing ativo pro Whisper (transcrição). Tier 3+.
4. **Anthropic** — chave da API Claude (evolução clínica). Tier 4.

---

## 2. Variáveis de ambiente (aba **Environment** do EasyPanel)

> O container **NÃO lê o `.env` do repo** (gitignored) — tudo vai na aba
> Environment do serviço no EasyPanel. Salvar reinicia o container.

### 2.1 Criptografia — OBRIGATÓRIA (bloqueia o boot)

`config/initializers/telemed.rb` dá **`raise` no boot em produção** se faltar a
chave primária. Motivo: `transcript_text` (transcrição) e `raw_markdown`/
`summary`/`reviewer_notes` (evolução) são **PII clínica criptografada** por
LGPD/CFM. Gere com `bin/rails db:encryption:init` e cole:

```
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

> Bypass **só** pra ambiente sem dados reais (staging/teste):
> `TELEMED_ALLOW_UNENCRYPTED=true`. **Nunca** em produção com paciente real.

### 2.2 LiveKit (Tier 1 — vídeo)

```
LIVEKIT_URL=wss://SEU-PROJETO.livekit.cloud
LIVEKIT_API_KEY=APIxxxxxxxx
LIVEKIT_API_SECRET=xxxxxxxxxxxxxxxxxxxx
# LIVEKIT_PUBLIC_URL — deixe VAZIO em prod. (Em dev separava a URL do browser
# da do backend; no Cloud é uma URL só pros dois.)
# LIVEKIT_EGRESS_URL — opcional; default = LIVEKIT_URL.
```

### 2.3 Storage das gravações — R2 (Tier 2)

`RecordingStorage` (download + signed URL) exige estas (dá erro se faltar):

```
TELEMED_STORAGE_BUCKET=klivy-telemed-recordings
TELEMED_STORAGE_ENDPOINT=https://<conta>.r2.cloudflarestorage.com
TELEMED_STORAGE_ACCESS_KEY_ID=...
TELEMED_STORAGE_SECRET_ACCESS_KEY=...
TELEMED_STORAGE_REGION=auto
```

> Em prod **não** setar `TELEMED_STORAGE_INTERNAL_ENDPOINT` (era só pro MinIO
> em container no dev). O Egress (Cloud) sobe direto no endpoint público do R2.

### 2.4 IA — transcrição e evolução (Tiers 3 e 4)

```
OPENAI_WHISPER_KEY=sk-...        # transcrição (Whisper). Cai na chave do
                                 # Captain (InstallationConfig) se vazia.
ANTHROPIC_API_KEY=sk-ant-...     # evolução (Claude Sonnet 4.6, default).
```

> Alternativa via banco: `OPENAI_WHISPER_KEY` e `ANTHROPIC_API_KEY` também são
> lidas de `InstallationConfig` (admin do app), além do ENV.

---

## 3. Webhook do Egress (pra gravação funcionar)

A gravação só completa quando o Egress avisa o app que terminou. Configure o
**webhook do LiveKit** apontando pro app de produção:

- **URL:** `https://SEU-DOMINIO/webhooks/livekit/egress`
- Assinado via JWT HS256 com o **mesmo `LIVEKIT_API_SECRET`** (o
  `Webhooks::Livekit::EgressController` valida).

No **LiveKit Cloud**: Project → Settings → Webhooks → adicionar a URL acima.
Sem isso o áudio sobe no R2 mas o `TranscribeRecordingJob` nunca dispara.

---

## 4. Config por clínica (não é env — é setting da conta)

Mesmo com tudo acima, a gravação só roda se a **clínica habilitar**. Em
`patient_portal_settings.telemedicine_recording` (JSONB por account):

```jsonc
{
  "enabled": true,                  // RecordingOrchestrator checa isso
  "auto_start": true,               // grava quando os 2 entram
  "patient_consent_required": true, // sem aceite do termo, NÃO grava (LGPD/CFM)
  "ai_evolution_enabled": true,
  "ai_provider": "claude-sonnet-4.6",
  "retention_days": 7300            // 20 anos (CFM)
}
```

- **`enabled=false`** → vídeo funciona, mas **não grava** (skip
  `recording_disabled`).
- **Consent:** o paciente aceita o termo LGPD no preflight; sem aceite o
  orchestrator pula a gravação (`consent_missing`). Nunca marque "gravado" sem
  consent real.

---

## 5. Já incluso na imagem (não precisa fazer nada)

- **Migrations** das tabelas (`telemed_recordings`, `proposed_evolutions`,
  `telemed_consents`, coluna `telemedicine_recording`) — rodam no deploy.
- **Sidekiq** processa os jobs (transcribe → evolution, no-show, quota). Já
  está no stack de prod.
- **Engine + rotas + frontend** — montados (`mount Telemed::Engine`).

---

## 6. Checklist de deploy

- [ ] 3 chaves `ACTIVE_RECORD_ENCRYPTION_*` no Environment (senão **não sobe**).
- [ ] `LIVEKIT_URL`/`API_KEY`/`API_SECRET` (LiveKit Cloud, com TURN).
- [ ] `LIVEKIT_PUBLIC_URL` **vazio**.
- [ ] Webhook do Egress apontando pro `…/webhooks/livekit/egress`.
- [ ] `TELEMED_STORAGE_*` (bucket R2) — se for gravar.
- [ ] `OPENAI_WHISPER_KEY` (transcrição) / `ANTHROPIC_API_KEY` (evolução).
- [ ] Clínica-piloto com `telemedicine_recording.enabled = true`.
- [ ] Build + push da imagem (tag = versão do CHANGELOG) + EasyPanel apontando
      pro novo tag + redeploy.
- [ ] Salvar env reinicia o container; **fix de código exige redeploy**.

---

## 7. Smoke test em produção

1. Criar/marcar uma consulta como teleconsulta (evento com
   `custom_attributes.telemedicine_enabled = true`).
2. Profissional entra na sala → vê o próprio vídeo (valida LiveKit + TURN).
3. Paciente entra pelo portal → sala de espera → profissional **Admite** →
   vídeo dos dois lados (valida admit server-side).
4. (Tier 2+) encerrar → conferir no R2 o `.ogg` + o status do
   `TelemedRecording` virar `transcribed`/`ready` → evolução na aba
   Teleconsulta.

---

## 8. Erros comuns (e a causa)

| Erro | Causa | Fix |
|---|---|---|
| App **não sobe** em prod | falta `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | setar as 3 chaves (§2.1) |
| `could not establish signal connection` | URL do LiveKit inalcançável pelo browser | use `wss://` público (Cloud); `LIVEKIT_PUBLIC_URL` vazio |
| Paciente em 4G **não conecta** vídeo | sem TURN | LiveKit Cloud (TURN gerenciado) ou `coturn` |
| `telemedicine_not_enabled` ao entrar | evento sem o flag | `custom_attributes.telemedicine_enabled=true` |
| Grava mas **não transcreve** | webhook do Egress não chega no app | configurar webhook (§3) |
| `ENV var TELEMED_STORAGE_* obrigatória` | storage não configurado | setar `TELEMED_STORAGE_*` (§2.3) |
| Gravação **pulada** | `enabled=false` ou consent ausente | habilitar na clínica + termo do paciente (§4) |

---

## Referências

- PRD do módulo: [`prd.md`](./prd.md)
- Integração com agenda: [`agenda-integration.md`](./agenda-integration.md)
- Auditoria: [`audit.md`](./audit.md)
- Deploy geral (imagem/EasyPanel): memória `project_deploy_docker_easypanel`
