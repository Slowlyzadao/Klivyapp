// API client de telemedicina (Sprint K).
import { http } from '@plugins/patient_portal/frontend/api/http';

export const telemedicineApi = {
  // POST /appointments/:id/telemedicine_token
  // Retorna { url, token, room, identity, name, ttl_seconds, dev_mode, room_code, ... }
  issueToken: appointmentId =>
    http.post(
      `/api/v1/patient_portal/telemed/sessions?event_id=${appointmentId}`
    ),

  // POST /appointments/:id/telemedicine_event { kind: 'joined' | 'left', recording_consent? }
  // Sprint L — opts.consented sinaliza aceite do termo de gravação no
  // preflight; backend persiste em PatientPortalConsent + custom_attributes.
  reportEvent: (appointmentId, kind, opts = {}) =>
    http.post(
      `/api/v1/patient_portal/telemed/sessions/event?event_id=${appointmentId}`,
      { kind, recording_consent: !!opts.consented }
    ),
};
