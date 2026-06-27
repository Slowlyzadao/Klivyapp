/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AiAgentTraining extends ApiClient {
  constructor() {
    super('ai_agent/training_conversations', { accountScoped: true });
  }

  get(page = 1) {
    return axios.get(this.url, { params: { page } });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // Upload multipart só do .zip — a clínica é escolhida depois, na detecção.
  create({ zipFile, name }) {
    const formData = new FormData();
    formData.append('training_conversation[zip_file]', zipFile);
    if (name) formData.append('training_conversation[name]', name);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // Aprova as FAQs mantidas e publica no RAG da Bea.
  publish(id, faqs) {
    return axios.post(`${this.url}/${id}/publish`, {
      training_conversation: { faqs },
    });
  }

  // Usuário escolheu qual participante é a clínica.
  selectClinic(id, clinicSenderName) {
    return axios.post(`${this.url}/${id}/select_clinic`, {
      training_conversation: { clinic_sender_name: clinicSenderName },
    });
  }

  // Aplica a mesma clínica a TODAS as conversas em awaiting_clinic que tenham
  // esse participante (auto-detecção do nome mais comum é feita no front).
  selectClinicBulk(clinicSenderName) {
    return axios.post(`${this.url}/select_clinic_bulk`, {
      clinic_sender_name: clinicSenderName,
    });
  }

  // mode: 'conversation' (arquiva, mantém FAQs) | 'all' (remove conversa + FAQs do RAG)
  delete(id, mode) {
    return axios.delete(`${this.url}/${id}`, { params: { mode } });
  }

  // Apaga TODAS as conversas visíveis de uma vez (mesmo `mode` do delete unitário).
  deleteAll(mode) {
    return axios.delete(`${this.url}/destroy_all`, { params: { mode } });
  }

  // Todas as FAQs sugeridas ainda não publicadas (de todas as conversas).
  pendingFaqs() {
    return axios.get(`${this.url}/pending_faqs`);
  }

  // Aprova em massa as FAQs selecionadas (ids "<conversa>-<índice>").
  approveAll(ids) {
    return axios.post(`${this.url}/approve_all`, { ids });
  }
}

export default new AiAgentTraining();
