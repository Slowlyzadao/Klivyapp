/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class FinancialGoalsAPI extends ApiClient {
  constructor() {
    super('financial/goals', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  update(data) {
    return axios.patch(this.url, data);
  }
}

export default new FinancialGoalsAPI();
