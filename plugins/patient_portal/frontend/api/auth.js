// Client da API de autenticação do portal. Funções correspondem 1-pra-1 com
// os endpoints `/api/v1/patient_portal/auth/*` (PRD §15.1).
import { http } from './http';

export const authApi = {
  requestOtp:    ({ identifier, channel }) => http.post('/api/v1/patient_portal/auth/request_otp', { identifier, channel }, { auth: false }),
  verifyOtp:     ({ identifier, code })    => http.post('/api/v1/patient_portal/auth/verify_otp',  { identifier, code },    { auth: false }),
  selectAccount: ({ tempToken, accountId }) => http.post('/api/v1/patient_portal/auth/select_account', { temp_token: tempToken, account_id: accountId }, { auth: false }),
  logout:        () => http.del('/api/v1/patient_portal/auth/logout'),
  me:            () => http.get('/api/v1/patient_portal/auth/me')
};
