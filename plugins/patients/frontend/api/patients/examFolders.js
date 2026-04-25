/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

const accountIdFromRoute = () =>
  window.location.pathname.match(/accounts\/(\d+)/)?.[1];

const apiVersion = '/api/v1';

const baseUrl = patientId =>
  `${apiVersion}/accounts/${accountIdFromRoute()}/patients/${patientId}/exam_folders`;

class ExamFoldersAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  getAll(patientId) {
    return axios.get(baseUrl(patientId));
  }

  update(patientId, folderId, data) {
    return axios.put(`${baseUrl(patientId)}/${folderId}`, {
      exam_folder: data,
    });
  }
}

export default new ExamFoldersAPI();
