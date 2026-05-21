/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class CriticalAlertsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  get url() {
    return `${this.baseUrl()}/${this.resource}`;
  }

  // Uses custom URL construction because it is nested under patients
  buildAlertUrl(patientId, alertId = null) {
    const base = `${this.url}/${patientId}/critical_alerts`;
    return alertId ? `${base}/${alertId}` : base;
  }

  get(patientId) {
    return axios.get(this.buildAlertUrl(patientId));
  }

  create(patientId, data) {
    return axios.post(this.buildAlertUrl(patientId), data);
  }

  update(patientId, alertId, data) {
    return axios.patch(this.buildAlertUrl(patientId, alertId), data);
  }

  deactivate(patientId, alertId) {
    return axios.patch(`${this.buildAlertUrl(patientId, alertId)}/deactivate`);
  }

  delete(patientId, alertId) {
    return axios.delete(this.buildAlertUrl(patientId, alertId));
  }
}

export default new CriticalAlertsAPI();
