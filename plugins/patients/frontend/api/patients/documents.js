/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class DocumentsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/documents`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { document: payload });
  }

  generate(patientId, payload) {
    // Server saves PDF to Active Storage and returns JSON doc metadata (:show view)
    // Use the /download endpoint separately to get the signed URL for the actual PDF
    return axios.post(`${this.buildUrl(patientId)}/generate`, payload);
  }

  download(patientId, documentId) {
    return axios.get(`${this.buildUrl(patientId)}/${documentId}/download`);
  }

  delete(patientId, documentId) {
    return axios.delete(`${this.buildUrl(patientId)}/${documentId}`);
  }

  sendWhatsApp(patientId, documentId) {
    return axios.post(
      `${this.buildUrl(patientId)}/${documentId}/send_whatsapp`
    );
  }
}

export default new DocumentsAPI();
