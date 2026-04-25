/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class SessionLogsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/session_logs`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  show(patientId, id) {
    return axios.get(`${this.buildUrl(patientId)}/${id}`);
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { session_log: payload });
  }

  delete(patientId, id) {
    return axios.delete(`${this.buildUrl(patientId)}/${id}`);
  }
}

export default new SessionLogsAPI();
