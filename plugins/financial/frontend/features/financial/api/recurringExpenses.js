/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class RecurringExpensesAPI extends ApiClient {
  constructor() {
    super('financial/recurring_expenses', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  create(payload) {
    return axios.post(this.url, { recurring_expense: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { recurring_expense: payload });
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new RecurringExpensesAPI();
