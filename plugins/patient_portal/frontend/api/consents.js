import { http } from './http';

export const consentsApi = {
  acceptPortalTerms: () => http.post('/api/v1/patient_portal/consents/portal_terms/accept'),
  acceptLgpd:        () => http.post('/api/v1/patient_portal/consents/lgpd/accept')
};
