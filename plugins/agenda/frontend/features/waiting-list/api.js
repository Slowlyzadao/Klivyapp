import ApiClient from 'dashboard/api/ApiClient';

class WaitingListEntriesAPI extends ApiClient {
  constructor() {
    super('waiting_list_entries', { accountScoped: true });
  }
}

export default new WaitingListEntriesAPI();
