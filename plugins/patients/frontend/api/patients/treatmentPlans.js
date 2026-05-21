/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class TreatmentPlansAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/treatment_plans`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  show(patientId, id) {
    return axios.get(`${this.buildUrl(patientId)}/${id}`);
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), { treatment_plan: payload });
  }

  update(patientId, id, payload) {
    return axios.put(`${this.buildUrl(patientId)}/${id}`, {
      treatment_plan: payload,
    });
  }

  // confirmCascade=true envia header X-Confirm-Cascade — usado quando o
  // backend respondeu 409 com `cascade_required: true` (PT tem Budget v2
  // aprovado SEM pagamento; canon Regra 3, cenário 2).
  destroy(patientId, id, { confirmCascade = false } = {}) {
    const config = confirmCascade
      ? { headers: { 'X-Confirm-Cascade': 'true' } }
      : {};
    return axios.delete(`${this.buildUrl(patientId)}/${id}`, config);
  }

  approve(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/approve`);
  }

  cancel(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/cancel`);
  }

  // Endpoint stable que sempre serve o blob ATUAL do PDF (resolve o problema
  // de cache da signed URL R2 após regeneração). Resposta como blob para
  // manter auth via header `api_access_token` — `window.open(rawUrl)` não
  // envia o header e retorna 401.
  downloadPdf(patientId, planId) {
    return axios.get(`${this.buildUrl(patientId)}/${planId}/pdf`, {
      responseType: 'blob',
    });
  }

  // Treatment Items nested resources
  getItems(patientId, planId) {
    return axios.get(`${this.buildUrl(patientId)}/${planId}/treatment_items`);
  }

  createItem(patientId, planId, payload) {
    return axios.post(`${this.buildUrl(patientId)}/${planId}/treatment_items`, {
      treatment_item: payload,
    });
  }

  updateItem(patientId, planId, itemId, payload) {
    return axios.put(
      `${this.buildUrl(patientId)}/${planId}/treatment_items/${itemId}`,
      {
        treatment_item: payload,
      }
    );
  }

  deleteItem(patientId, planId, itemId) {
    return axios.delete(
      `${this.buildUrl(patientId)}/${planId}/treatment_items/${itemId}`
    );
  }
}

export default new TreatmentPlansAPI();
