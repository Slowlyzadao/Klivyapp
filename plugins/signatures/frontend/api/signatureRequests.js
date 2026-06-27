/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Cliente HTTP do plugin signatures.
// Endpoints registrados em plugins/signatures/config/routes.rb sob
// /api/v1/accounts/:accountId/signature_requests/*.
class SignatureRequestsAPI extends ApiClient {
  constructor() {
    super('signature_requests', { accountScoped: true });
  }

  list({ signableType, signableId, status } = {}) {
    return axios.get(this.url, {
      params: {
        signable_type: signableType,
        signable_id: signableId,
        status,
      },
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(payload) {
    // payload: { signable_type, signable_id, signer_name, signer_email,
    //            signer_phone?, signer_cpf?, message?, provider? }
    return axios.post(this.url, payload);
  }

  cancel(id, { reason } = {}) {
    return axios.post(`${this.url}/${id}/cancel`, { reason });
  }

  resend(id) {
    return axios.post(`${this.url}/${id}/resend`);
  }

  refreshStatus(id) {
    return axios.post(`${this.url}/${id}/refresh_status`);
  }
}

export const signatureRequestsApi = new SignatureRequestsAPI();
