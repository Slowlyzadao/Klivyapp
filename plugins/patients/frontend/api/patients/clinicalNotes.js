/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ClinicalNotesAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/clinical_notes`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { clinical_note: payload });
  }

  update(patientId, noteId, payload) {
    return axios.patch(`${this.buildUrl(patientId)}/${noteId}`, {
      clinical_note: payload,
    });
  }

  sign(patientId, noteId) {
    return axios.patch(`${this.buildUrl(patientId)}/${noteId}/sign`);
  }

  delete(patientId, noteId) {
    return axios.delete(`${this.buildUrl(patientId)}/${noteId}`);
  }
}

export default new ClinicalNotesAPI();
