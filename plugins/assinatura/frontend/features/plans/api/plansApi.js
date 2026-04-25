import { getCsrfToken } from '../../../shared/constants.js';

const BASE_URL = '/super_admin/subscription_plans';

const headers = () => ({
  'Content-Type': 'application/json',
  'X-CSRF-Token': getCsrfToken(),
});

async function parseResponse(res) {
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((body.errors || []).join(', ') || `Erro ${res.status}`);
  return body;
}

export const plansApi = {
  list() {
    return fetch(`${BASE_URL}.json`).then(parseResponse);
  },

  create(data) {
    return fetch(`${BASE_URL}.json`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({ subscription_plan: data }),
    }).then(parseResponse);
  },

  update(id, data) {
    return fetch(`${BASE_URL}/${id}.json`, {
      method: 'PATCH',
      headers: headers(),
      body: JSON.stringify({ subscription_plan: data }),
    }).then(parseResponse);
  },

  destroy(id) {
    return fetch(`${BASE_URL}/${id}.json`, {
      method: 'DELETE',
      headers: headers(),
    }).then(res => {
      if (!res.ok) throw new Error(`Erro ${res.status}`);
    });
  },
};
