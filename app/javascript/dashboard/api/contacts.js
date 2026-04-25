/* global axios */
import ApiClient from './ApiClient';

export const buildContactParams = (
  page,
  sortAttr,
  label,
  search,
  pageSize = 15
) => {
  let params = `include_contact_inboxes=false&page=${page}&sort=${sortAttr}&page_size=${pageSize}`;
  if (search) {
    params = `${params}&q=${search}`;
  }
  if (label) {
    params = `${params}&labels[]=${label}`;
  }
  return params;
};

class ContactAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  get(page, sortAttr = 'name', label = '', pageSize = 15) {
    let requestURL = `${this.url}?${buildContactParams(
      page,
      sortAttr,
      label,
      '',
      pageSize
    )}`;
    return axios.get(requestURL);
  }

  show(id) {
    return axios.get(`${this.url}/${id}?include_contact_inboxes=false`);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}?include_contact_inboxes=false`, data);
  }

  getConversations(contactId) {
    return axios.get(`${this.url}/${contactId}/conversations`);
  }

  getContactableInboxes(contactId) {
    return axios.get(`${this.url}/${contactId}/contactable_inboxes`);
  }

  getContactLabels(contactId) {
    return axios.get(`${this.url}/${contactId}/labels`);
  }

  initiateCall(contactId, inboxId) {
    return axios.post(`${this.url}/${contactId}/call`, {
      inbox_id: inboxId,
    });
  }

  updateContactLabels(contactId, labels) {
    return axios.post(`${this.url}/${contactId}/labels`, { labels });
  }

  search(search = '', page = 1, sortAttr = 'name', label = '', pageSize = 15) {
    let requestURL = `${this.url}/search?${buildContactParams(
      page,
      sortAttr,
      label,
      search,
      pageSize
    )}`;
    return axios.get(requestURL);
  }

  active(page = 1, sortAttr = 'name', pageSize = 15) {
    let requestURL = `${this.url}/active?${buildContactParams(page, sortAttr, '', '', pageSize)}`;
    return axios.get(requestURL);
  }

  // eslint-disable-next-line default-param-last
  filter(page = 1, sortAttr = 'name', queryPayload, pageSize = 15) {
    let requestURL = `${this.url}/filter?${buildContactParams(page, sortAttr, '', '', pageSize)}`;
    return axios.post(requestURL, queryPayload);
  }

  importContacts(file) {
    const formData = new FormData();
    formData.append('import_file', file);
    return axios.post(`${this.url}/import`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  destroyCustomAttributes(contactId, customAttributes) {
    return axios.post(`${this.url}/${contactId}/destroy_custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  destroyAvatar(contactId) {
    return axios.delete(`${this.url}/${contactId}/avatar`);
  }

  exportContacts(queryPayload) {
    return axios.post(`${this.url}/export`, queryPayload);
  }
}

export default new ContactAPI();
