// API client do Web Push (Sprint G).
// Conversa com o backend pra trocar a chave VAPID e registrar subscriptions.
import { http } from './http';

export const pushApi = {
  publicKey: () => http.get('/api/v1/patient_portal/push_subscriptions/public_key'),
  subscribe: subscription => http.post('/api/v1/patient_portal/push_subscriptions', { subscription }),
  unsubscribe: endpoint   => http.del(`/api/v1/patient_portal/push_subscriptions?endpoint=${encodeURIComponent(endpoint)}`)
};
