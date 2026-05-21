/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class BeClinicPermissionsAPI extends ApiClient {
  constructor() {
    super('beclinic_permissions', { accountScoped: true });
  }

  // GET /api/v1/accounts/:account_id/beclinic_permissions
  fetchPermissions() {
    return axios.get(this.url);
  }
}

export default new BeClinicPermissionsAPI();
