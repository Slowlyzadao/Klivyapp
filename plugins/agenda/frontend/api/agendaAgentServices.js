/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Vínculo profissional↔serviço (quais serviços um agente atende).
// Backend: plugins/agenda/app/controllers/api/v1/accounts/agenda_agent_services_controller.rb
class AgendaAgentServicesAPI extends ApiClient {
  constructor() {
    super('agenda_agent_services', { accountScoped: true });
  }

  // GET → { services: [{ id, name }], selected_ids: [Number] }
  getForAgent(userId) {
    return axios.get(this.url, { params: { user_id: userId } });
  }

  // PUT /:userId  { service_ids } → { selected_ids }
  setForAgent(userId, serviceIds) {
    return axios.put(`${this.url}/${userId}`, { service_ids: serviceIds });
  }
}

export default new AgendaAgentServicesAPI();
