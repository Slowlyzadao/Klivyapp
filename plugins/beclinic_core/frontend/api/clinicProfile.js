/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

/**
 * ClinicProfileAPI — perfil institucional da clínica (especialidades atendidas
 * e padrão). Endpoint singleton scoped pela conta corrente; não tem `:id`.
 *
 * Backend: `Api::V1::Accounts::ClinicProfileController`.
 *
 * Forma da resposta:
 *   { default_specialty: 'Estética Facial' | null,
 *     enabled_specialties: ['Estética Facial', 'Avaliação Clínica'] }
 */
class ClinicProfileAPI extends ApiClient {
  constructor() {
    super('clinic_profile', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.patch(this.url, data);
  }
}

export default new ClinicProfileAPI();
