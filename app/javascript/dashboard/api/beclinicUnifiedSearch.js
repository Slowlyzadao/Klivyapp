/* global axios */
import ApiClient from './ApiClient';

class BeclinicUnifiedSearchAPI extends ApiClient {
  constructor() {
    super('beclinic_unified_search', { accountScoped: true });
  }

  search({ q }) {
    return axios.get(this.url, { params: { q } });
  }
}

export default new BeclinicUnifiedSearchAPI();
