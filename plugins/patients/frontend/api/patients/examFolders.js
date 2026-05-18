/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// API REST para pastas relacionadas a um paciente.
// Backend: ExamFoldersController (RESTful, fonte de verdade na tabela `exam_folders`).
const accountIdFromRoute = () =>
  window.location.pathname.match(/accounts\/(\d+)/)?.[1];

const baseUrl = patientId =>
  `/api/v1/accounts/${accountIdFromRoute()}/patients/${patientId}/exam_folders`;

class ExamFoldersAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  // GET /exam_folders → { data: [{id, name, color, parent_id, position, ...}] }
  getAll(patientId) {
    return axios.get(baseUrl(patientId));
  }

  // POST /exam_folders → cria pasta. payload: { name, color, parent_id, position }
  create(patientId, payload) {
    return axios.post(baseUrl(patientId), { exam_folder: payload });
  }

  // PATCH /exam_folders/:id → atualiza nome/cor/parent/posição
  update(patientId, folderId, payload) {
    return axios.patch(`${baseUrl(patientId)}/${folderId}`, {
      exam_folder: payload,
    });
  }

  // DELETE /exam_folders/:id → exclui pasta (subpastas vão junto, arquivos vão para raiz)
  delete(patientId, folderId) {
    return axios.delete(`${baseUrl(patientId)}/${folderId}`);
  }

  // PUT /exam_folders/reorder → aplica reordenação em batch.
  // items: [{ id, parent_id, position }, ...]
  reorder(patientId, items) {
    return axios.put(`${baseUrl(patientId)}/reorder`, { items });
  }
}

export default new ExamFoldersAPI();
