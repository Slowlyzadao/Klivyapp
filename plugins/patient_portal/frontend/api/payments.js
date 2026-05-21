// Cliente das APIs de pagamento online (PRD §9 — Sprint F).
import { http } from './http';

const BASE = '/api/v1/patient_portal/payments';

export const paymentsApi = {
  create:       ({ installmentId, method }) =>
                  http.post(BASE, { installment_id: installmentId, method }),
  get:          (id) => http.get(`${BASE}/${id}`),
  cancel:       (id) => http.post(`${BASE}/${id}/cancel`),
  simulatePaid: (id) => http.post(`${BASE}/${id}/simulate_paid`) // dev only
};
