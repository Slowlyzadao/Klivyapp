// Cliente das APIs de perfil + LGPD export.
import { http } from './http';

export const profileApi = {
  get:    ()      => http.get('/api/v1/patient_portal/profile'),
  update: (attrs) => http.patch('/api/v1/patient_portal/profile', attrs),
  lgpdExport: () => http.post('/api/v1/patient_portal/lgpd/exports')
};
