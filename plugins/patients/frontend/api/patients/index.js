/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

export const buildPatientParams = ({
  page,
  perPage,
  sort,
  search,
  status,
  financialStatus,
}) => {
  const params = new URLSearchParams();
  params.set('page', page);
  params.set('per_page', perPage);
  if (sort) params.set('sort', sort);
  if (search) params.set('q', search);
  if (status && status !== 'Todos') params.set('status', status);
  if (financialStatus) params.set('financial_status', financialStatus);
  return params.toString();
};

class PatientsAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { patient: data });
  }

  get({
    page = 1,
    perPage = 25,
    sort = 'name_asc',
    search = '',
    status = '',
    financialStatus = '',
  } = {}) {
    const requestURL = `${this.url}?${buildPatientParams({
      page,
      perPage,
      sort,
      search,
      status,
      financialStatus,
    })}`;
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
