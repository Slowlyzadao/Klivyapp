# 07 — Fluxos End-to-End

Cada fluxo descrito como sequência cronológica: quem dispara → o que acontece → estado resultante. Útil pra debugar e replicar.

---

## 7.1 Fluxo 1: Consulta agendada → vídeo entre dentista e paciente

### 7.1.1 Pré-condições
- `AgendaEvent` criado com `custom_attributes.telemedicine_enabled = true`.
- `account.patient_portal_setting.telemedicine_recording.enabled = true`.
- ENV LiveKit configurado.

### 7.1.2 Sequência

```
Tempo  Quem            Ação
-----  -------------   ----------------------------------------------------
T-15m  Dentista        Abre dashboard, vê card na aba "Próximas". Click "Entrar"
                       → frontend `useTelemedicineJoin.join(event)`
                       → POST /telemedicine_token
                       
T-15m  Backend         SessionsController#create chama Telemed::Session.new
                       → resolve estado (enabled, within window).
                       → SessionIssuer.call → JWT com canPublish:true
                       → retorna { url, token, room_code }
                       
T-15m  Frontend        Salva token em sessionStorage.
                       window.open('/agenda/telemed/:eventId', '_blank')
                       
T-15m  Dentista        TelemedRoomPage.vue monta.
                       Lê token de sessionStorage (ou re-issue se F5).
                       Renderiza TelemedicineRoom com props.
                       
T-15m  Frontend        TelemedicineRoom.vue:
                       - new Room()
                       - room.connect(url, token)
                       - room.localParticipant.enableCameraAndMicrophone()
                       - POST /telemedicine_event { kind: 'joined' }
                       
T-15m  Backend         SessionsController#event chama SessionEventHandler.joined!
                       - Registra doctor_joined_at em custom_attributes
                       - Marca event.status: 'arrived' se 'confirmed'
                       - Enfileira MarkNoShowJob(5min)
                       
T-15m  LiveKit         Dentista visível na sala. Sem paciente ainda.

T-5m   Paciente        Acessa patient portal (push notification ou email com link)
                       Vê TelemedicineJoinCard inline na consulta.
                       Click "Entrar".
                       → POST /patient_portal/telemed/sessions
                       
T-5m   Backend         PatientPortal::SessionsController:
                       - SessionIssuer.call (canPublish: !outside_window)
                       - Retorna { url, token, requires_admit: false }
                       
T-5m   Patient SPA     TelemedicineRoomPage.vue → TelemedicineRoom.
                       Conecta. Publica mic/cam. POST event 'joined'.
                       Pergunta consent gravação no momento do joined.
                       
T-5m   Backend         joined! (paciente):
                       - Registra patient_joined_at.
                       - Cancela MarkNoShowJob (paciente chegou).
                       - Marca both_started_at agora.
                       - Enfileira MarkInProgressJob(5min) — se ambos
                         ainda presentes em 5min, status: 'in_progress'.
                       
T-5m   LiveKit         Doutor vê paciente entrando. Ambos visíveis.
T+0    Ambos           Consulta acontece (vídeo + áudio em tempo real).
                       Dentista pode iniciar/parar gravação manual (opcional).
                       
T+30m  Doutor          Click "Encerrar pra todos".
                       Frontend envia DataPacket { type: 'call_ended' }
                       no canal lossy.
                       room.disconnect()
                       
T+30m  Paciente        Recebe DataPacket → emit('ended-by-host')
                       → window.location = '/'
                       
T+30m  Doutor          Modal pós-encerramento: "Conseguiu atender?"
                       Click "Sim" → POST /confirm_completed
                       → event.status: 'completed'
```

### 7.1.3 Estados finais
- `AgendaEvent.status`: `completed`
- `TelemedRecording.status`: depende se gravação foi iniciada (`pending` se não)

---

## 7.2 Fluxo 2: Gravação automática durante chamada

### 7.2.1 Pré-condições adicionais
- `setting.telemedicine_recording.auto_start = true` (configuração da conta).
- `TelemedConsent` ativo do paciente.

### 7.2.2 Sequência

```
T+0    SessionEventHandler  joined! detecta ambos presentes
                            → RecordingOrchestrator.start!(event)
                            
T+0    RecordingOrchestrator
                            - Cria TelemedRecording(status: 'pending')
                            - LiveKit::EgressService.start_participant_egress
                              × 2 (doctor + patient)
                            - LiveKit::EgressService.start_room_composite_egress
                            - Persiste 3 egress_ids
                            
T+0~1s LiveKit         POST /webhooks/livekit/egress
                       { event: 'egress_started', egressInfo: { egressId: 'EG_xxx' } }
                       × 3 (um por job)
                       
T+0~1s Webhook         EgressController valida JWT + SHA-256.
                       Atualiza recording.status: 'recording'.
                       Broadcast ActionCable → frontend mostra "Gravando..."
                       
T+0~30 LiveKit         Captura áudio em background. Encoding OGG mono opus 64k.
                       Streams pra R2 em chunks.
                       
T+30m  Doutor          Encerra chamada (todos saem).
T+30m  LiveKit         Detecta room vazia → finaliza egress jobs.
                       Upload final pra R2 (3 arquivos):
                       - doctor_EG_xxx.ogg
                       - patient_EG_xxx.ogg
                       - composite_EG_xxx.ogg
                       POST /webhooks/livekit/egress
                       { event: 'egress_ended', fileResults: [...] } × 3
                       
T+30m  Webhook         Pra cada egress_ended:
                       - Persist storage_key (doctor/patient/composite)
                       - Marca role como concluído
                       - Quando TODOS concluídos:
                         → recording.update!(status: 'uploaded')
                         → TranscribeRecordingJob.perform_later
                       
T+30m  ActionCable     Frontend recebe status → "Processando transcrição..."
```

---

## 7.3 Fluxo 3: Transcrição (OpenAI gpt-4o-transcribe-diarize)

### 7.3.1 Trigger
- `recording.status: 'uploaded'` → `TranscribeRecordingJob.perform_later(recording_id)`.

### 7.3.2 Sequência (job em background, queue `:low`)

```
T+30m  Sidekiq         Pega job da queue.
                       
       TranscribeRecordingJob:
       1. recording.update!(status: 'transcribing')
       2. recording.broadcast_status_change!
       3. Download paralelo do R2:
          - doctor.ogg (tmpfile)
          - patient.ogg (tmpfile)
       4. provider = TranscriptionProvider.for(setting.transcription_provider)
                     # default: 'gpt-4o-transcribe-diarize'
       5. result = provider.call(
            doctor_audio_path: '/tmp/doctor.ogg',
            patient_audio_path: '/tmp/patient.ogg'
          )
       6. recording.update!(
            status: 'transcribed',
            transcript_text: result.text,
            transcript_segments: result.segments
          )
       7. recording.broadcast_status_change!
       8. Deleta do R2: doctor.ogg, patient.ogg
          (composite preservado pro player do dashboard)
       9. GenerateEvolutionJob.perform_later(recording_id)
       
T+33m  Frontend        ActionCable → "Gerando evolução..."
```

### 7.3.3 Whisper fallback

Se setting indica `transcription_provider: 'whisper'`, o flow é diferente:
- 2 chamadas paralelas pra Whisper (doctor + patient separados, sem diarização nativa).
- Pós-processamento merge cronológico pra reconstruir conversa.
- WER pior (~5% vs ~2.5% do gpt-4o), mas mais barato.

### 7.3.4 Falhas

- Arquivo > 25MB → `PermanentFailure` → `discard_on` (sem retry, marca `failed`).
- Erro 5xx OpenAI → retry exponential (3×). Após esgotar, `recording.fail!`.
- Timeout (default Sidekiq 30s? OpenAI pode levar minutos pra áudios longos) → ajustar `sidekiq_options retry_in: 5.minutes`.

---

## 7.4 Fluxo 4: Geração de evolução (Anthropic Claude)

### 7.4.1 Trigger
- `recording.status: 'transcribed'` → `GenerateEvolutionJob.perform_later(recording_id)`.

### 7.4.2 Sequência

```
T+33m  Sidekiq         GenerateEvolutionJob:
                       
       1. recording.update!(status: 'evolving')
       2. provider_name = resolve_provider_name(account)
                          # lê account.patient_portal_setting.telemedicine_recording['ai_provider']
                          # default: 'claude-sonnet-4.6'
       3. patient_context = build_patient_context(event):
          - name, age (calc de birth_date)
          - allergies (custom_attributes['allergies'])
          - current_medications
          - 3 últimas ClinicalNotes do paciente (histórico)
       4. provider = EvolutionProvider.for(provider_name)
                     # → EvolutionProvider::Claude
       5. result = provider.call(
            transcript: recording.transcript_text,
            patient_context: patient_context
          )
       
       Internamente:
       a) sanitize_transcript (gsub backticks fences pra evitar prompt injection)
       b) build_user_message (contexto + transcript + tarefa)
       c) RubyLLM.context.chat(
            model: 'claude-sonnet-4-6',
            assume_model_exists: true,
            provider: :anthropic
          ).with_instructions(SYSTEM_PROMPT)
       d) chat.ask(user_content) → response.content (markdown)
       e) parse_response (markdown → struct):
          - extract_soap_sections (## S, ## O, ## A, ## P)
          - extract_summary (## Resumo Executivo)
          - extract_json_blocks (regex ```json ... ```)
          - parse_attention_points (array)
          - parse_procedure_fields (hash 14 chaves)
       
       6. ProposedEvolution.create!(
            telemed_recording: recording,
            provider: 'claude/claude-sonnet-4-6',
            soap_structure: result.soap_structure,
            raw_markdown: result.raw_markdown,
            summary: result.summary,
            attention_points: result.attention_points,
            procedure_fields: result.procedure_fields,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            status: 'pending_review'
          )
       7. recording.update!(status: 'ready')
       8. recording.broadcast_status_change!
       9. notify_dentist (cria PatientPortalNotification in-app)
       10. EnforceRecordingQuotaJob.perform_later
       
T+34m  Frontend        ActionCable → "Aguardando revisão"
                       Dashboard mostra badge "Aguarda revisão"
                       Card destacado em "Finalizadas".
```

### 7.4.3 Idempotência (re-enqueue)

Partial unique index `(recording_id) WHERE status='pending_review'` impede duplicatas. Se job rodar 2× (retry duplicado):

```ruby
rescue ActiveRecord::RecordNotUnique
  existing = recording.proposed_evolutions.where(status: 'pending_review').first
  existing&.update!(procedure_fields: result.procedure_fields, ...)
end
```

Aproveita a existente em vez de criar órfã.

### 7.4.4 Falhas

- Transcript > 600k chars → `PermanentFailure` (TODO: chunking).
- ANTHROPIC_API_KEY ausente → erro inicial, recording marca `failed`.
- API timeout/5xx → 3 retries exponential. Após esgotar, `recording.fail!` (mantém transcript pro dentista escrever manual).

---

## 7.5 Fluxo 5: Revisão + Aprovação humana

### 7.5.1 Pré-condições
- `ProposedEvolution.status: 'pending_review'`.
- Dentista é dono do `AgendaEvent` (ou admin).

### 7.5.2 Sequência

```
T+34m+ Dentista        Abre dashboard. Tab "Finalizadas".
                       Vê card destacado "Aguarda revisão".
                       Click → /teleconsultas/86 (TeleconsultaDetailPage)
                       
       Frontend        Fetch detail → mostra:
                       - Banner: paciente + status + data
                       - Player de áudio (composite signed URL)
                       - Transcrição (com karaokê sync ao player)
                       - Resumo da Teleconsulta (markdown)
                       - Pontos de Atenção (lateral, sticky)
                       - Registrar Procedimento (form full-width, 14 campos)
                       
       Dentista        Ouve áudio + lê transcrição.
                       Revisa Pontos de Atenção (alergias, contraindicações).
                       Revisa cada campo do Registro de Procedimento.
                       Edita os que precisar (badge "BIA" some).
                       
                       Salvar Rascunho (opcional):
                       PATCH /proposed_evolutions/40
                       body: { procedure_fields: { ... } }
                       → status: 'edited'
                       
                       Quando pronto:
                       - Marca checkbox: "Confirmo que li, revisei e concordo..."
                       - Click "Salvar e Assinar"
                       → window.confirm("Aplicar ao prontuário?")
                       → PATCH /proposed_evolutions/40 (se há mudanças)
                       → POST /proposed_evolutions/40/approve
                       
       Backend         ProposedEvolutionsController#approve:
                       → ProposedEvolutionApprovalService.call
                       
                       Service (transação):
                       1. build_session_log(evolution):
                          patient_id, professional_id, appointment_id,
                          performed_at, duration_minutes,
                          procedure_name (de procedure_fields['procedimento_realizado']),
                          complaint_of_day (de queixa_do_dia),
                          assessment (de avaliacao_clinica),
                          complications (de intercorrencias),
                          result_observed (de resultado_imediato),
                          next_consultation_details, observation,
                          return_in_days, return_needed,
                          areas_treated [{ region, description }],
                          products_used [{ name, quantity, unit, batch, expires_at }],
                          status: 'draft'
                       2. session_log.save!
                       3. evolution.update!(
                            status: 'approved',
                            reviewed_by: actor,
                            reviewed_at: Time.current
                          )
                       4. session_log.update_column(:proposed_evolution_id, evolution.id)
                       
                       Response:
                       { data: <evolution>, clinical_note: { id: 42, status: 'draft' } }
                       
       Frontend        emit('approved', { evolution, clinical_note })
                       → detail.value.evolution = evolution
                       → alert("Evolução aplicada (#42)")
                       
T+35m  Dentista        Navega pra Pacientes > Bruna > Evolução
                       Tab "Ficha Clínica": vê o SessionLog #42 (status draft).
                       Tab "Histórico de Evolução": tabular view com mesma entrada.
                       Pode assinar/editar como qualquer outra session log.
```

### 7.5.3 Rejeição

```
       Dentista        Click "Recusar"
                       Modal pede justificativa (obrigatória).
                       → POST /proposed_evolutions/40/reject
                          body: { reason: "..." }
                       → status: 'rejected'
                       → reviewer_notes: '...' (auditoria CFM)
                       
                       NENHUM SessionLog é criado.
                       Dentista pode escrever evolução manual ou
                       chamar reevolve pra IA tentar de novo.
```

---

## 7.6 Fluxo 6: Real-time UI updates (ActionCable)

```
Backend         model.broadcast_status_change!
                Publica em ActionCable channel "account_<id>":
                {
                  event: 'telemed.recording.status_changed',
                  data: {
                    agenda_event_id: 86,
                    recording_id: 96,
                    status: 'ready',
                    has_transcript: true,
                    has_audio: true
                  }
                }
                
Browser         Klivy core tem listener global no canal account_<id>.
                Eventos com prefixo telemed.* são re-emitidos via mitt
                bus interno (BUS_EVENTS.TELEMED_RECORDING_UPDATED).
                
DetailPage      onMounted:
                emitter.on(BUS_EVENTS.TELEMED_RECORDING_UPDATED, onTelemedRecordingUpdated)
                
                Handler:
                - Ignora se agenda_event_id ≠ atual
                - Atualiza detail.value.recording.status inline
                - Em transições terminais (transcribed/ready/failed):
                  fetchDetail() — refetch completo
```

Resultado: dashboard atualiza em tempo real sem F5. Status muda de "Processando..." → "Aguarda revisão" → "Aplicada ao prontuário" automaticamente.

---

## 7.7 Fluxo 7: Re-transcrição / Re-evolução (admin recovery)

Cenários: transcrição saiu ruim, modelo IA muito velho, mudou ai_provider.

```
Admin          Click "Re-transcrever" no detail (admin-only button).
               → POST /teleconsultas/86/retranscribe
               
Backend        TeleconsultasController#retranscribe:
               - recording.update!(status: 'transcribed' → 'uploaded')
                 (reset state pra TranscribeJob aceitar)
               - TranscribeRecordingJob.perform_later
               - Mantém ProposedEvolution existente até nova ser gerada
               
Sidekiq        Re-roda TranscribeRecordingJob + GenerateEvolutionJob.
               Nova ProposedEvolution(status: 'pending_review') criada.
               
               Se já existia uma ProposedEvolution 'approved' antiga:
               - Permanece aprovada (não é destruída)
               - Mas a "latest_proposed_evolution" agora é a nova pending
               
Dentista       Vê dashboard atualizado com novo "Aguarda revisão".
               Pode aprovar a nova versão (cria 2° SessionLog).
```

---

## 7.8 Fluxo 8: Quota enforcement (housekeeping)

```
Trigger        Pós-GenerateEvolutionJob (quando nova recording → ready)
               
EnforceRecordingQuotaJob:
1. quota = setting.telemedicine_recording['max_active_recordings'] || 15
2. active = account.telemed_recordings
              .where(archived_at: nil)
              .order(created_at: :desc)
3. return if active.count <= quota
4. active.offset(quota).each(&:archive!)

archive! (no model):
- Deleta do R2: composite_audio_key (último arquivo restante)
- Limpa columns *_audio_key (NULL)
- Set archived_at: Time.current
- Mantém: transcript_text, transcript_segments, evolutions, FK pro SessionLog

Resultado: histórico permanece consultável (texto), mas storage não cresce indefinidamente.
```

`recording.archived?` é true → `recording_url` endpoint retorna 410 Gone.

---

## 7.9 Fluxo 9: Consentimento LGPD do paciente

```
Patient SPA    No modal de entrar na sala, exibe checkbox:
               "Concordo com gravação da consulta para fins de prontuário (LGPD)"
               
Paciente       Marca → click "Entrar"
               → POST /patient_portal/telemed/sessions/event
                  body: { kind: 'joined', recording_consent: true }
               
Backend        Se recording_consent: true:
               TelemedConsent.accept!(
                 account: account,
                 patient: patient,
                 term_version: 'v1',  # versionável
                 ip: request.remote_ip,
                 user_agent: request.user_agent
               )
               
               Idempotência:
               - Se já existe ativo: retorna existente.
               - Se revogado: revoked_at = nil (re-aceite).
               - Senão: cria.
               
               Sem consent: gravação NÃO pode iniciar (validado em
               RecordingOrchestrator.start! antes de chamar LiveKit).
```

### Revogação

Endpoint não implementado no MVP (descomissionar requer escrita manual). Trilha:

```ruby
TelemedConsent.find(id).update!(revoked_at: Time.current, revoke_reason: '...')
```

Após revogação, próximas teleconsultas exigem novo consent.
