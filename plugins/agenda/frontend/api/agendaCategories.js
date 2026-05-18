import ApiClient from 'dashboard/api/ApiClient';

class AgendaCategoriesAPI extends ApiClient {
  constructor() {
    super('agenda_categories', { accountScoped: true });
  }

  reorder(ids) {
    return this.update('reorder', { ids });
  }
}

export default new AgendaCategoriesAPI();
