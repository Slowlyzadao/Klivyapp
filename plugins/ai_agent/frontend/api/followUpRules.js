/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AiAgentFollowUpRules extends ApiClient {
  constructor() {
    super('ai_agent/follow_up_rules', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { follow_up_rule: data });
  }

  update(id, data) {
    return axios.put(`${this.url}/${id}`, { follow_up_rule: data });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new AiAgentFollowUpRules();
