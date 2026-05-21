/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AgendaServicesAPI extends ApiClient {
  constructor() {
    super('agenda_services', { accountScoped: true });
  }

  reorder(ids) {
    return this.update('reorder', { ids });
  }

  // PR #7 da auditoria 2026-05-13: GET /agenda_services/:id/usage_stats
  // Retorna { agenda_events_count, treatment_items_count } pra modal de
  // delete defensivo. O método show() do ApiClient base monta o path correto.
  usageStats(id) {
    return axios.get(`${this.url}/${id}/usage_stats`);
  }

  // PR de UI overhaul (2026-05-14): index paginado.
  // GET /agenda_services?page=N&per_page=10&q=search&archived=true|false
  // Retorna { services: [...com counts], meta: { current_page, total_pages, ... } }.
  // `archived=true` lista soft-deletados (deleted_at preenchido) em vez de kept.
  // Endpoint legado (sem params) segue retornando array para o calendário.
  getPaginated({ page = 1, perPage = 10, q = '', archived = false } = {}) {
    return axios.get(this.url, {
      params: { page, per_page: perPage, q, archived },
    });
  }

  // GET /agenda_services/cleanup_unused_preview → { count, ids }
  cleanupUnusedPreview() {
    return axios.get(`${this.url}/cleanup_unused_preview`);
  }

  // POST /agenda_services/cleanup_unused → { cleaned_count, ids }
  // Hard-delete em massa de serviços sem nenhum vínculo. IRREVERSÍVEL.
  // UI exige confirmação via checkbox antes do botão habilitar.
  cleanupUnused() {
    return axios.post(`${this.url}/cleanup_unused`);
  }

  // PR de arquivados (2026-05-14):
  // POST /agenda_services/:id/restore → { (service) }
  restore(id) {
    return axios.post(`${this.url}/${id}/restore`);
  }

  // DELETE /agenda_services/:id/destroy_permanently → 200
  // Hard-delete (IRREVERSÍVEL). Use só após confirmação dupla na UI.
  destroyPermanently(id) {
    return axios.delete(`${this.url}/${id}/destroy_permanently`);
  }
}

export default new AgendaServicesAPI();
