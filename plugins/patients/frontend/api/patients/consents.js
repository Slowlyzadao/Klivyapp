/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ConsentsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  // Fetch all consent records for a patient
  get(patientId) {
    return axios.get(`${this.url}/${patientId}/consents`);
  }

  // Fetch pending consent records for a patient
  getPending(patientId) {
    return axios.get(`${this.url}/${patientId}/consents/pending`);
  }

  // Create a new consent record
  create(patientId, payload) {
    return axios.post(`${this.url}/${patientId}/consents`, payload);
  }

  // Get a specific consent record
  show(patientId, consentId) {
    return axios.get(`${this.url}/${patientId}/consents/${consentId}`);
  }

  // Sign a specific consent record
  sign(patientId, consentId, signatureData) {
    return axios.post(`${this.url}/${patientId}/consents/${consentId}/sign`, {
      signature: signatureData,
    });
  }

  // Send a specific consent record for remote signature
  sendRemote(patientId, consentId) {
    return axios.post(
      `${this.url}/${patientId}/consents/${consentId}/send_remote`
    );
  }

  // Revoke a specific consent record
  revoke(patientId, consentId) {
    return axios.patch(`${this.url}/${patientId}/consents/${consentId}/revoke`);
  }

  // Delete a consent record
  delete(patientId, consentId) {
    return axios.delete(`${this.url}/${patientId}/consents/${consentId}`);
  }
}

export default new ConsentsAPI();
