// Cliente das APIs de anamnese (read-only no MVP, opt-in via clínica).
import { http } from './http';

const BASE = '/api/v1/patient_portal/anamneses';

export const anamnesesApi = {
  list: () => http.get(BASE),
  get:  (id) => http.get(`${BASE}/${id}`)
};
