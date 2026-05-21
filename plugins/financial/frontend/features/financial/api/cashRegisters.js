/* global axios */
const base = accountId =>
  `/api/v1/accounts/${accountId}/financial/cash_registers`;

export default {
  list(accountId, params = {}) {
    return axios.get(base(accountId), { params });
  },
  show(accountId, id) {
    return axios.get(`${base(accountId)}/${id}`);
  },
  create(accountId, payload) {
    return axios.post(base(accountId), payload);
  },
  update(accountId, id, payload) {
    return axios.patch(`${base(accountId)}/${id}`, payload);
  },
  destroy(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
};
