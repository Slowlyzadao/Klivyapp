/* global axios */
import ApiClient from './ApiClient';

class AccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  createAccount(data) {
    return axios.post(`${this.apiVersion}/accounts`, data);
  }

  async getCacheKeys() {
    const response = await axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/cache_keys`
    );
    return response.data.cache_keys;
  }

  // Dados da clínica (custom_attributes + logo) — alimenta as variáveis
  // clinic.* dos documentos. Endpoint dedicado (clinic_profile), pois o
  // serializer do Account não expõe essas chaves.
  getClinicProfile() {
    return axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/clinic_profile`
    );
  }

  updateClinicProfile(data) {
    return axios.patch(
      `/api/v1/accounts/${this.accountIdFromRoute}/clinic_profile`,
      data
    );
  }
}

export default new AccountAPI();
