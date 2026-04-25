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

  destroy(patientId, id) {
    return axios.delete(`${this.buildUrl(patientId)}/${id}`);
  }

  approve(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/approve`);
  }

  cancel(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/cancel`);
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
