// Cliente das APIs de mensagens (bridge para Chatwoot Conversation/Message).
import { http } from './http';

const BASE = '/api/v1/patient_portal/messages';

export const messagesApi = {
  list:   () => http.get(BASE),
  send:   (content) => http.post(BASE, { content }),
  triage: (content) => http.post(`${BASE}/triage`, { content })
};
