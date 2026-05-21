// Cliente das ações de recall (dismiss + schedule_intent).
import { http } from './http';

const BASE = '/api/v1/patient_portal/recall';

export const recallApi = {
  dismiss:         () => http.post(`${BASE}/dismiss`),
  scheduleIntent:  () => http.post(`${BASE}/schedule_intent`)
};
