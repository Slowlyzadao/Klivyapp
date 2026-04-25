/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class FinancialDashboardAPI extends ApiClient {
  constructor() {
    super('financial/dashboard', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new FinancialDashboardAPI();
