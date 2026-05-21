/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AuditLogsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildLogUrl(patientId) {
    return `${this.url}/${patientId}/audit_logs`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildLogUrl(patientId), { params });
  }

  export(patientId) {
    return axios.get(`${this.buildLogUrl(patientId)}/export`, {
      responseType: 'blob', // To handle PDF download
    });
  }
}

export default new AuditLogsAPI();
