/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AccountTransactionsAPI extends ApiClient {
  constructor() {
    super('financial/transactions', { accountScoped: true });
  }

  list(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, { account_transaction: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { account_transaction: data });
  }

  receive(id, { paymentMethod, paidAt, bankAccountId, proofFile }) {
    const form = new FormData();
    form.append('payment_method', paymentMethod);
    form.append('received_at', paidAt);
    if (bankAccountId) form.append('bank_account_id', bankAccountId);
    if (proofFile) form.append('proof_file', proofFile);
    return axios.post(`${this.url}/${id}/receive`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new AccountTransactionsAPI();
