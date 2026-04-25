/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class CommissionRulesAPI extends ApiClient {
  constructor() {
    super('financial/commission_rules', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  create(payload) {
    return axios.post(this.url, { commission_rule: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { commission_rule: payload });
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new CommissionRulesAPI();
