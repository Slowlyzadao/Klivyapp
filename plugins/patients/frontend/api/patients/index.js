/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

export const buildPatientParams = (page, sortAttr, search, status) => {
  let params = `page=${page}&sort=${sortAttr}`;
  if (search) {
    params = `${params}&q=${search}`;
  }
  if (status && status !== 'Todos') {
    params = `${params}&status=${status}`;
  }
  return params;
};

class PatientsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { patient: data });
  }

  get(page = 1, sortAttr = 'name', search = '', status = '') {
    let requestURL = `${this.url}?${buildPatientParams(
      page,
      sortAttr,
      search,
      status
    )}&per_page=50000`;
    return axios.get(requestURL);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  summary(id) {
    return axios.get(`${this.url}/${id}/summary`);
  }

  byContact(contactId) {
    return axios.get(`${this.url}/by_contact`, {
      params: { contact_id: contactId },
    });
  }

  updateStatus(id, status) {
    return axios.patch(`${this.url}/${id}/status`, { patient_status: status });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { patient: data });
  }

  updateAvatar(id, file) {
    const formData = new FormData();
    formData.append('patient[avatar]', file);
    return axios.patch(`${this.url}/${id}`, formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });
  }

  changeHistory(id) {
    return axios.get(`${this.url}/${id}/change_history`);
  }

  archived(search = '') {
    const params = search ? `?q=${search}` : '';
    return axios.get(`${this.url}/archived${params}`);
  }

  restore(id) {
    return axios.patch(`${this.url}/${id}/restore`);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new PatientsAPI();
