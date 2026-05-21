// Cliente das APIs de pedidos de documento (2ª via).
import { http } from './http';

const BASE = '/api/v1/patient_portal/document_requests';

export const documentRequestsApi = {
  list:   () => http.get(BASE),
  create: (payload) => http.post(BASE, payload),
  cancel: (id, reason) => http.del(`${BASE}/${id}`, { body: { reason } })
};
