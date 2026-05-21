import { http } from './http';

const BASE = '/api/v1/patient_portal/notifications';

export const notificationsApi = {
  list:        () => http.get(BASE),
  markAllRead: () => http.post(`${BASE}/mark_all_read`),
  markRead:    (id) => http.post(`${BASE}/${id}/mark_read`)
};
