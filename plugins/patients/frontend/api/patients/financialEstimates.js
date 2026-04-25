/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class FinancialEstimatesAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/financial_estimates`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  show(patientId, id) {
    return axios.get(`${this.buildUrl(patientId)}/${id}`);
  }

  create(patientId, payload) {
    return axios.post(this.buildUrl(patientId), {
      financial_estimate: payload,
    });
  }

  update(patientId, id, payload) {
    return axios.put(`${this.buildUrl(patientId)}/${id}`, {
      financial_estimate: payload,
    });
  }

  approve(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/approve`);
  }

  cancel(patientId, id) {
    return axios.patch(`${this.buildUrl(patientId)}/${id}/cancel`);
  }
}

export default new FinancialEstimatesAPI();
