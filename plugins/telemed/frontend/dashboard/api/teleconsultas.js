/* global axios */
/* eslint-disable max-classes-per-file -- ambos os clientes pertencem ao
   módulo de Teleconsulta e compartilham o mesmo scope (telemed/*). */
import ApiClient from 'dashboard/api/ApiClient';

// Sprint L — API client da aba Teleconsulta (clínica).
// account-scoped: /api/v1/accounts/:accountId/teleconsultas/*
class TeleconsultasAPI extends ApiClient {
  constructor() {
    super('telemed/teleconsultas', { accountScoped: true });
  }

  list({
    tab = 'upcoming',
    page = 1,
    perPage = 20,
    professionalId,
    dateFrom,
    dateTo,
  } = {}) {
    return axios.get(this.url, {
      params: {
        tab,
        page,
        per_page: perPage,
        professional_id: professionalId,
        date_from: dateFrom,
        date_to: dateTo,
      },
    });
  }

  show(eventId) {
    return axios.get(`${this.url}/${eventId}`);
  }

  // Contagens por aba — alimenta os badges de Próximas/Em andamento/etc.
  counts() {
    return axios.get(`${this.url}/counts`);
  }

  // kind: 'doctor_video' | 'patient_video' | 'composite' | 'doctor_audio' | 'patient_audio'
  recordingUrl(eventId, kind) {
    return axios.get(`${this.url}/${eventId}/recording_url`, {
      params: { kind },
    });
  }

  retranscribe(eventId) {
    return axios.post(`${this.url}/${eventId}/retranscribe`);
  }

  reevolve(eventId) {
    return axios.post(`${this.url}/${eventId}/reevolve`);
  }
}

class ProposedEvolutionsAPI extends ApiClient {
  constructor() {
    super('telemed/proposed_evolutions', { accountScoped: true });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  approve(id) {
    return axios.post(`${this.url}/${id}/approve`);
  }

  reject(id, reason) {
    return axios.post(`${this.url}/${id}/reject`, { reason });
  }
}

export const teleconsultasApi = new TeleconsultasAPI();
export const proposedEvolutionsApi = new ProposedEvolutionsAPI();
