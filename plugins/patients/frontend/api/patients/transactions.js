/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class TransactionsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/transactions`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  show(patientId, id) {
    return axios.get(`${this.buildUrl(patientId)}/${id}`);
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { transaction: payload });
  }

  delete(patientId, id) {
    return axios.delete(`${this.buildUrl(patientId)}/${id}`);
  }

  pay(patientId, id, payload = {}) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/pay`, payload);
  }

  refund(patientId, id, payload = {}) {
    return axios.post(`${this.buildUrl(patientId)}/${id}/refund`, payload);
  }

  chargeWhatsapp(patientId, id) {
    return axios.post(`${this.buildUrl(patientId)}/${id}/charge_whatsapp`);
  }

  getSummary(patientId) {
    return axios.get(`${this.url}/${patientId}/financial_summary`);
  }

  uploadProof(patientId, id, file) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.buildUrl(patientId)}/${id}/upload_proof`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  getProofUrl(patientId, id) {
    return axios.get(`${this.buildUrl(patientId)}/${id}/proof_url`);
  }
}

export default new TransactionsAPI();
