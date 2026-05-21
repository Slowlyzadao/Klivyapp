/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AgendaSettingsAPI extends ApiClient {
  constructor() {
    super('agenda_setting', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.put(this.url, { agenda_setting: data });
  }
}

export default new AgendaSettingsAPI();
