/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class PatientAppointmentsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/appointments`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { appointment: payload });
  }

  // Auditoria UX 2026-05-15: métodos `reschedule`, `cancel` e `markNoShow`
  // removidos junto com os botões da aba de prontuário. Operação de agenda
  // fica exclusiva do calendário principal. Endpoints backend também foram
  // removidos do PatientAppointmentsController.

  sendRecall(patientId) {
    return axios.post(`${this.url}/${patientId}/recall`);
  }
}

export default new PatientAppointmentsAPI();
