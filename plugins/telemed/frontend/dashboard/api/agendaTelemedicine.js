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
}

export default new AgendaTelemedicineAPI();
