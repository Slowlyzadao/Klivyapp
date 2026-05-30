# 06 — APIs e Endpoints HTTP

> Todos os endpoints exigem autenticação por `api_access_token` (header) exceto o webhook do LiveKit (autenticação por JWT no header `Authorization`).
>
> `:account_id` na URL é o ID da conta autenticada. O backend valida via Pundit.

---

## 6.1 Endpoints da clínica (dashboard)

### 6.1.1 Lista de teleconsultas

```
GET /api/v1/accounts/:account_id/telemed/teleconsultas
```

**Query params**:
- `tab`: `upcoming` | `in_progress` | `finished` | `no_show`
- `page`: int (default 1)
- `per_page`: int (default 20, max 100)
- `professional_id`: int (opcional)
- `date_from`: ISO8601 (opcional)
- `date_to`: ISO8601 (opcional)

**Response 200**:
```json
{
  "data": [
    {
      "id": 86,
      "starts_at": "2026-05-25T15:29:00-03:00",
      "ends_at": "2026-05-25T15:59:00-03:00",
      "duration_minutes": 30,
      "status": "completed",
      "service": "Avaliação",
      "reason": "Dor de dente molar",
      "patient": { "id": 12, "patient_id": 12, "name": "Bruna Lopes Oliveira" },
      "professional": { "id": 73, "name": "Dr. Admin" },
      "recording": { "id": 96, "status": "ready", "has_transcript": true }
    }
  ],
  "meta": { "page": 1, "per_page": 20, "total_count": 1, "total_pages": 1 }
}
```

### 6.1.2 Contagens (badges das abas)

```
GET /api/v1/accounts/:account_id/telemed/teleconsultas/counts
```

**Response 200**:
```json
{
  "data": {
    "upcoming": 5,
    "in_progress": 0,
    "finished": 12,
    "no_show": 2
  }
}
```

### 6.1.3 Detalhe de teleconsulta

```
GET /api/v1/accounts/:account_id/telemed/teleconsultas/:event_id
```

**Response 200**:
```json
{
  "data": {
    "id": 86,
    "starts_at": "2026-05-25T15:29:00-03:00",
    "ends_at": "2026-05-25T15:59:00-03:00",
    "duration_minutes": 30,
    "status": "completed",
    "service": "Avaliação",
    "reason": "Dor de dente molar",
    "room_code": "klivy-acc1-ev86",
    "patient": { "id": 12, "name": "Bruna Lopes Oliveira" },
    "professional": { "id": 73, "name": "Dr. Admin" },
    "recording": {
      "id": 96,
      "status": "ready",
      "has_transcript": true,
      "has_audio": true,
      "transcript_segments": [
        { "start": 1.2, "end": 4.8, "text": "Bom dia...", "speaker": "doctor" }
      ],
      "transcript_text": "..."
    },
    "evolution": {
      "id": 40,
      "status": "pending_review",
      "provider": "claude/claude-sonnet-4-6",
      "soap_structure": { "subjetivo": "...", "objetivo": "...", "avaliacao": "...", "plano": "..." },
      "raw_markdown": "...",
      "summary": "Paciente relata dor **fixa** em região posterior...",
      "attention_points": [
        { "type": "systemic", "severity": "medium", "text": "Paciente relata bruxismo..." }
      ],
      "procedure_fields": {
        "queixa_do_dia": "...",
        "avaliacao_clinica": "...",
        "procedimento_realizado": "Teleconsulta de avaliação",
        "area_tratada": "",
        "produto_utilizado": "",
        "quantidade_dose": "",
        "unidade": "",
        "lote": "",
        "validade": "",
        "intercorrencias": "",
        "resultado_imediato": "...",
        "detalhes_proxima_consulta": "...",
        "retorno_em_dias": 1,
        "observacao": "..."
      },
      "reviewed_by": null,
      "reviewed_at": null,
      "clinical_note_id": null
    }
  }
}
```

### 6.1.4 URL assinada de gravação

```
GET /api/v1/accounts/:account_id/telemed/teleconsultas/:event_id/recording_url?kind=composite_audio
```

**Kind values**: `composite_audio` | `doctor_audio` | `patient_audio` (vídeo não está implementado no MVP).

**Response 200**:
```json
{
  "data": {
    "url": "https://abc.r2.cloudflarestorage.com/telemed/...?X-Amz-Expires=300&...",
    "expires_at": "2026-05-26T12:35:00Z"
  }
}
```

URL tem TTL de 5 min. Se o player tomar 403 mid-playback (URL expirou enquanto buffer), o frontend refaz GET (retomando posição atual).

### 6.1.5 Re-transcrever (admin)

```
POST /api/v1/accounts/:account_id/telemed/teleconsultas/:event_id/retranscribe
```

Re-enfileira `TranscribeRecordingJob`. Útil se a transcrição saiu ruim (ruído, modelo antigo). Bloqueia se `recording.archived?`.

**Response 200**:
```json
{ "data": { "status": "enqueued" } }
```

### 6.1.6 Re-gerar evolução (admin)

```
POST /api/v1/accounts/:account_id/telemed/teleconsultas/:event_id/reevolve
```

Re-enfileira `GenerateEvolutionJob`. Cria nova `ProposedEvolution` (status `pending_review`). A anterior fica como "histórica" se já tinha sido aprovada.

---

## 6.2 Endpoints de revisão (proposed_evolutions)

### 6.2.1 Update (edição do dentista)

```
PATCH /api/v1/accounts/:account_id/telemed/proposed_evolutions/:id
```

**Body** (todos opcionais):
```json
{
  "soap_structure": {
    "subjetivo": "...",
    "objetivo": "...",
    "avaliacao": "...",
    "plano": "..."
  },
  "raw_markdown": "...",
  "procedure_fields": {
    "queixa_do_dia": "Editado pelo dentista",
    "retorno_em_dias": 7
  }
}
```

Whitelist obrigatória (rejeita keys desconhecidas). Marca `status: 'edited'` se vinha de `pending_review`.

**Response 200**:
```json
{ "data": { /* mesmo formato do detail.evolution */ } }
```

**Response 422**:
```json
{ "error": "Proposta já aprovada" }
```

### 6.2.2 Approve (vira SessionLog)

```
POST /api/v1/accounts/:account_id/telemed/proposed_evolutions/:id/approve
```

Sem body.

**Response 200**:
```json
{
  "data": { /* evolution atualizada com status: 'approved' */ },
  "clinical_note": { "id": 42, "status": "draft" }
}
```

Apesar do nome legacy `clinical_note`, o ID retornado é de um `SessionLog`. Frontend só usa `id` e `status` — não inspeciona o tipo.

### 6.2.3 Reject

```
POST /api/v1/accounts/:account_id/telemed/proposed_evolutions/:id/reject
```

**Body**:
```json
{ "reason": "Diagnóstico incorreto — paciente não tem o sintoma descrito." }
```

`reason` é **obrigatório** (compliance CFM — trilha de auditoria).

**Response 200**:
```json
{ "data": { /* evolution com status: 'rejected', reviewer_notes: '...' */ } }
```

---

## 6.3 Endpoints da sala (clínica)

> Os endpoints abaixo são montados em `agenda_events` nested (legado). Caminho real:
>
> `POST /api/v1/accounts/:account_id/agenda_events/:event_id/<action>`

### 6.3.1 Emitir token (dentista)

```
POST /api/v1/accounts/:account_id/agenda_events/:event_id/telemedicine_token
```

Sem body.

**Response 200** (sucesso):
```json
{
  "data": {
    "url": "wss://livekit.exemplo.com",
    "token": "eyJ...",
    "room_code": "klivy-acc1-ev86",
    "dev_mode": false,
    "outside_window": false,
    "requires_admit": false,
    "initial_admissions": []
  }
}
```

**Response 200** (fora da janela, doutor não bloqueado):
```json
{
  "data": {
    "url": "wss://...",
    "token": "...",
    "outside_window": true,
    "starts_in_seconds": 600,
    "too_early": true
  }
}
```

**Response 403** (bloqueado):
```json
{ "error": "Telemedicina desativada nesta conta." }
```

### 6.3.2 Reportar evento da sala

```
POST /api/v1/accounts/:account_id/agenda_events/:event_id/telemedicine_event
```

**Body**:
```json
{ "kind": "joined" }
```

ou:

```json
{ "kind": "left" }
```

**Response 200**:
```json
{ "data": { "status": "ok" } }
```

Side effects:
- `joined` (doutor): pode marcar `event.status: 'arrived'` se ainda `confirmed`. Enfileira `MarkNoShowJob` (5min).
- `joined` (paciente, depois): pode marcar `in_progress` (via `MarkInProgressJob`).
- `left`: apenas registra timestamp em `custom_attributes['telemed_session']`. **Não** marca `completed`.

### 6.3.3 Admitir paciente (waiting room)

```
POST /api/v1/accounts/:account_id/agenda_events/:event_id/telemedicine/admit_patient
```

**Body**:
```json
{ "identity": "patient-12" }
```

Chama `LiveKit::RoomService#update_participant` liberando `canPublish: true`.

**Response 200**:
```json
{ "data": { "admitted": "patient-12" } }
```

### 6.3.4 Iniciar gravação (manual)

```
POST /api/v1/accounts/:account_id/agenda_events/:event_id/telemedicine/start_recording
```

**Body opcional**:
```json
{ "force": true }
```

`force: true` ignora setting "auto-iniciar gravação". Sempre exige consent do paciente (validado server-side).

**Response 200**:
```json
{ "data": { "recording_id": 96, "status": "pending" } }
```

**Response 422** (sem consent):
```json
{ "error": "Paciente ainda não consentiu com a gravação." }
```

### 6.3.5 Parar gravação

```
POST /api/v1/accounts/:account_id/agenda_events/:event_id/telemedicine/stop_recording
```

**Response 200**:
```json
{ "data": { "recording_id": 96, "status": "uploaded" } }
```

### 6.3.6 Confirmar atendimento (pós-encerramento)

```
POST /api/v1/accounts/:account_id/agenda_events/:event_id/telemedicine/confirm_completed
```

Único caminho legal pra marcar `event.status: 'completed'`. UI mostra modal "Conseguiu atender?" após o doutor sair da sala.

**Response 200**:
```json
{ "data": { "status": "completed" } }
```

---

## 6.4 Endpoints do paciente (Patient Portal)

> Patient Portal corre em host separado: `pacientes.<dominio>`. Endpoints abaixo são consumidos pela SPA do paciente.

### 6.4.1 Emitir token (paciente)

```
POST /api/v1/patient_portal/telemed/sessions?event_id=:event_id
```

**Headers**: cookie de sessão do Patient Portal (Devise).

**Response 200**:
```json
{
  "data": {
    "url": "wss://...",
    "token": "eyJ...",
    "room_code": "klivy-acc1-ev86",
    "outside_window": false,
    "requires_admit": false
  }
}
```

Token emitido com `canPublish: false` se `requires_admit: true` (paciente entrou fora da janela). Senão, `canPublish: true`.

### 6.4.2 Reportar evento (paciente)

```
POST /api/v1/patient_portal/telemed/sessions/event?event_id=:event_id
```

**Body**:
```json
{
  "kind": "joined",
  "recording_consent": true
}
```

`recording_consent` cria `TelemedConsent` ativo (idempotente — não duplica se já aceito).

**Response 200**:
```json
{ "data": { "status": "ok" } }
```

---

## 6.5 Webhook LiveKit (server → server)

```
POST /webhooks/livekit/egress
```

**Auth**: header `Authorization: <JWT>` (HS256, secret = `LIVEKIT_WEBHOOK_KEY || LIVEKIT_API_KEY`).

**Body** (exemplos):

```json
{
  "event": "egress_started",
  "egressInfo": {
    "egressId": "EG_xxx",
    "roomName": "klivy-acc1-ev86",
    "status": "EGRESS_ACTIVE"
  },
  "sha256": "...",
  "id": "evt_xxx",
  "createdAt": "1700000000"
}
```

```json
{
  "event": "egress_ended",
  "egressInfo": {
    "egressId": "EG_xxx",
    "roomName": "klivy-acc1-ev86",
    "status": "EGRESS_COMPLETE",
    "fileResults": [{
      "filename": "telemed/account_1/event_86/composite_EG_xxx.ogg",
      "size": 28_500_000,
      "duration": 1800
    }]
  }
}
```

**Response 200**:
```json
{ "ok": true }
```

**Idempotência**: webhook chega 2-3x (LiveKit retries). Service usa `find_or_create_by(egress_id:)` + `recording.with_lock` pra evitar duplicar transitions.

---

## 6.6 Exemplos de chamadas curl

### Listar teleconsultas finalizadas
```bash
curl -H "api_access_token: $TOKEN" \
  "$API/api/v1/accounts/1/telemed/teleconsultas?tab=finished&page=1&per_page=10"
```

### Approve evolução
```bash
curl -X POST -H "api_access_token: $TOKEN" \
  "$API/api/v1/accounts/1/telemed/proposed_evolutions/40/approve"
```

### Update procedure_fields
```bash
curl -X PATCH -H "api_access_token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"procedure_fields":{"queixa_do_dia":"Texto editado","retorno_em_dias":7}}' \
  "$API/api/v1/accounts/1/telemed/proposed_evolutions/40"
```

### Emitir token (dentista)
```bash
curl -X POST -H "api_access_token: $TOKEN" \
  "$API/api/v1/accounts/1/agenda_events/86/telemedicine_token"
```

---

## 6.7 Códigos de erro recorrentes

| HTTP | Cenário |
|------|---------|
| 401 | `api_access_token` ausente/inválido |
| 403 | Sem permissão (Pundit) — outro profissional, ou telemedicina desativada |
| 404 | Evento/recording/evolution não pertence à conta |
| 422 | Validação (proposta já aprovada, sem consent, transição inválida) |
| 500 | Erro de infra (R2 inacessível, ENV var faltando) |

Frontend trata via try/catch + `error.response.data.error`.
