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

  update(patientId, id, payload) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}`, {
      session_log: payload,
    });
  }

  delete(patientId, id) {
    return axios.delete(`${this.buildUrl(patientId)}/${id}`);
  }

  sign(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/sign`);
  }

  markErratum(patientId, id, reason) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/mark_erratum`, {
      reason,
    });
  }

  signPatientLocally(patientId, id, { signature, deviceInfo } = {}) {
    return axios.post(
      `${this.buildUrl(patientId)}/${id}/sign_patient_locally`,
      {
        signature,
        device_info: deviceInfo,
      }
    );
  }

  sendPatientRemoteSignatureLink(patientId, id, payload = {}) {
    return axios.post(
      `${this.buildUrl(patientId)}/${id}/send_patient_remote_signature_link`,
      payload
    );
  }
}

export default new SessionLogsAPI();
