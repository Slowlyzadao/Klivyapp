/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AiAgentInternalNotificationTemplates extends ApiClient {
  constructor() {
    super('ai_agent/internal_notification_templates', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { internal_notification_template: data });
  }

  update(id, data) {
    return axios.put(`${this.url}/${id}`, { internal_notification_template: data });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  reset(id) {
    return axios.post(`${this.url}/${id}/reset`);
  }

  catalog() {
    return axios.get(`${this.url}/catalog`);
  }
}

export default new AiAgentInternalNotificationTemplates();
