/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AgendaNotificationLogsAPI extends ApiClient {
  constructor() {
    super('agenda_notification_logs', { accountScoped: true });
  }

  /**
   * Busca logs de notificação com filtros opcionais
   * @param {Object} params - { status, rule_id, page, per_page }
   */
  getLogs(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new AgendaNotificationLogsAPI();
