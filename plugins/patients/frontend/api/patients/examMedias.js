/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class ExamMediasAPI extends ApiClient {
  constructor() {
    super('patients', { accountScoped: true });
  }

  buildUrl(patientId) {
    return `${this.url}/${patientId}/exams`;
  }

  get(patientId, params = {}) {
    return axios.get(this.buildUrl(patientId), { params });
  }

  create(patientId, payload) {
    const formData = new FormData();
    formData.append('exam_media[category]', payload.category || 'outro');
    if (payload.description)
      formData.append('exam_media[description]', payload.description);
    if (payload.notes)
      formData.append('exam_media[description]', payload.notes);
    if (payload.file) formData.append('exam_media[file]', payload.file);

    return axios.post(this.buildUrl(patientId), formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress: payload.onUploadProgress,
    });
  }

  delete(patientId, mediaId) {
    return axios.delete(`${this.buildUrl(patientId)}/${mediaId}`);
  }
}

export default new ExamMediasAPI();
