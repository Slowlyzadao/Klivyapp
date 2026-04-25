/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AgendaNotificationRulesAPI extends ApiClient {
  constructor() {
    super('agenda_notification_rules', { accountScoped: true });
  }

  /**
   * Alterna o estado enabled/disabled de uma regra
   * @param {number} id - ID da regra
   */
  toggle(id) {
    return axios.patch(`${this.url}/${id}/toggle`);
  }
}

export default new AgendaNotificationRulesAPI();
