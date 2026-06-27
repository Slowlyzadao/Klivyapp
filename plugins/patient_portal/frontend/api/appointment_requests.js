// Cliente das APIs de pedidos de agendamento.
import { http } from './http';

const BASE = '/api/v1/patient_portal/appointment_requests';

export const appointmentRequestsApi = {
  list:   () => http.get(BASE),
  create: (payload) => http.post(BASE, payload),
  cancel: (id, reason) => http.del(`${BASE}/${id}`, { body: { reason } })
};
