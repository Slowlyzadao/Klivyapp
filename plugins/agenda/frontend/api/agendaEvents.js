/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AgendaEventsAPI extends ApiClient {
  constructor() {
    super('agenda_events', { accountScoped: true });
  }

  // ApiClient.get() do core não aceita params (ignora argumentos), por isso
  // chamamos axios diretamente aqui — caso contrário starts_at/ends_at seriam
  // silenciosamente descartados e o backend devolveria os 500 eventos mais
  // antigos via cap, deixando a semana atual vazia na UI.
  filter({ userId, contactId, status, startsAt, endsAt }) {
    const params = {};
    if (userId) params.user_id = userId;
    if (contactId) params.contact_id = contactId;
    if (status) params.status = status;
    if (startsAt) params.starts_at = startsAt;
    if (endsAt) params.ends_at = endsAt;

    return axios.get(this.url, { params });
  }

  // Agregação por dia para a Year View. Backend retorna breakdown por status
  // pra permitir filtros client-side sem novo round-trip.
  yearStats({ year, userId } = {}) {
    const params = { year };
    if (userId) params.user_id = userId;
    return axios.get(`${this.url}/year_stats`, { params });
  }

  // Soft-delete com motivo + nota. Backend exige `reason` e (se reason='outro')
  // `note` não-vazio. Evento permanece visível no prontuário do paciente
  // (Agenda e Histórico + Timeline) com badge de status correspondente.
  softDelete(id, { reason, note } = {}) {
    return axios.delete(`${this.url}/${id}`, {
      data: { reason, note: note || '' },
    });
  }
}

export default new AgendaEventsAPI();
