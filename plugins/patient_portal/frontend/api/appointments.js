// Cliente das APIs de consultas — espelha o controller do backend.
import { http } from './http';

const BASE = '/api/v1/patient_portal/appointments';

export const appointmentsApi = {
  list:    () => http.get(BASE),
  get:     (id) => http.get(`${BASE}/${id}`),
  confirm: (id) => http.post(`${BASE}/${id}/confirm`),
  cancel:  (id, reason) => http.post(`${BASE}/${id}/cancel`, { reason })
};
