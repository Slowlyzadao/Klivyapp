// API client de dependentes (Sprint I).
//
// list   → GET  /dependents          (retorna acting/active/accessible)
// switch → POST /dependents/switch   (muda active_patient_id na sessão)
import { http } from './http';

export const dependentsApi = {
  list:   ()           => http.get('/api/v1/patient_portal/dependents'),
  switch: (patientId)  => http.post('/api/v1/patient_portal/dependents/switch', { patient_id: patientId })
};
