// Cliente das APIs de consentimento clínico (ConsentRecord).
import { http } from './http';

const BASE = '/api/v1/patient_portal/consent_records';

export const consentRecordsApi = {
  list: () => http.get(BASE),
  get:  (id) => http.get(`${BASE}/${id}`),
  sign: (id, signatureBlob) => http.post(`${BASE}/${id}/sign`, { signature_blob: signatureBlob })
};
