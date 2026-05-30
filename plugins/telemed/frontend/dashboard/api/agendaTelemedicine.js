/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Sprint K admin-side — endpoint pra gerar token LiveKit pro profissional
// responsável entrar na sala. Espelha o telemedicineApi do patient_portal,
// mas com path account-scoped e role='doctor' (decidido pelo backend).
class AgendaTelemedicineAPI extends ApiClient {
  constructor() {
    // accountScoped = true → resolve /api/v1/accounts/:accountId/agenda_events
    super('telemed/sessions', { accountScoped: true });
  }

  // POST /api/v1/accounts/:accountId/agenda_events/:id/telemedicine_token
  // Retorna { data: { url, token, room, identity, name, ttl_seconds, dev_mode } }
  issueToken(eventId) {
    return axios.post(`${this.url}?event_id=${eventId}`);
  }

  // POST /api/v1/accounts/:accountId/agenda_events/:id/telemedicine_event
  // Sprint K — frontend reporta joined/left pra acionar automação de
  // status. role='doctor' é inferido no backend pelo controller (admin).
  reportEvent(eventId, kind) {
    return axios.post(`${this.url}/event?event_id=${eventId}`, { kind });
  }

  // POST /api/v1/accounts/:accountId/telemed/sessions/confirm_completed?event_id=:id
  // Doutor confirmou no modal pós-encerramento que de fato atendeu o paciente.
  // Marca o evento como 'completed' — única forma de chegar nesse status
  // agora que `SessionEventHandler#left!` não auto-transiciona (mudança
  // 2026-05-21: evita "atendido" automático quando a chamada falhou).
  confirmCompleted(eventId) {
    return axios.post(`${this.url}/confirm_completed?event_id=${eventId}`);
  }

  // POST /api/v1/accounts/:accountId/telemed/sessions/admit_patient
  // 2026-05-21 — Server-side waiting room. Dentista clica "Aceitar" no card
  // → este endpoint chama LiveKit UpdateParticipant pra liberar canPublish
  // do paciente. Sem isso, o paciente fica em waiting room indefinidamente
  // (token foi emitido com canPublish=false).
  admitPatient(eventId, identity) {
    return axios.post(`${this.url}/admit_patient?event_id=${eventId}`, {
      identity,
    });
  }

  // POST /api/v1/accounts/:accountId/telemed/sessions/start_recording
  // 2026-05-22 — Gravação manual da consulta. Doutor clica no botão "Gravar"
  // na toolbar da sala → backend chama RecordingOrchestrator com force:true
  // (pula auto-enable do setting da conta; consent do paciente segue
  // obrigatório). Substitui o auto-start no `joined` que falhava silencioso.
  startRecording(eventId) {
    return axios.post(`${this.url}/start_recording?event_id=${eventId}`);
  }

  // POST /api/v1/accounts/:accountId/telemed/sessions/stop_recording
  // Doutor clica de novo no botão (estado ON) → para todos os Egress.
  stopRecording(eventId) {
    return axios.post(`${this.url}/stop_recording?event_id=${eventId}`);
  }
}

export default new AgendaTelemedicineAPI();
