/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class PatientTimelineAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/timeline`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }
}

export default new PatientTimelineAPI();
