import ApiClient from 'dashboard/api/ApiClient';

class AgendaServicesAPI extends ApiClient {
  constructor() {
    super('agenda_services', { accountScoped: true });
  }

  reorder(ids) {
    return this.update('reorder', { ids });
  }
}

export default new AgendaServicesAPI();
