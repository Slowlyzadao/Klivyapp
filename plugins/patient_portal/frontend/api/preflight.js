// Cliente do endpoint de pré-flight (avaliação consultiva antes de agendar).
import { http } from './http';

export const preflightApi = {
  appointment: () => http.get('/api/v1/patient_portal/preflight/appointment')
};
