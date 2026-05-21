/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AnamnesisAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/anamneses`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { anamnesis: payload });
  }

  update(patientId, anamnesisId, payload) {
    return axios.patch(`${this.buildUrl(patientId)}/${anamnesisId}`, {
      anamnesis: payload,
    });
  }

  finalize(patientId, anamnesisId) {
    return axios.patch(`${this.buildUrl(patientId)}/${anamnesisId}/finalize`);
  }
}

export default new AnamnesisAPI();
