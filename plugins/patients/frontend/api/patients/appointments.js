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

  reschedule(patientId, id, payload) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/reschedule`, {
      appointment: payload,
    });
  }

  cancel(patientId, id, reason = '') {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/cancel`, {
      cancellation_reason: reason,
    });
  }

  markNoShow(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/no_show`);
  }

  sendRecall(patientId) {
    return axios.post(`${this.url}/${patientId}/recall`);
  }
}

export default new PatientAppointmentsAPI();
