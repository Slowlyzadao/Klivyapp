/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class BankAccountsAPI extends ApiClient {
  constructor() {
    super('financial/bank_accounts', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, data);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new BankAccountsAPI();
