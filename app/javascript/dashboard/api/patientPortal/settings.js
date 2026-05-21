/* global axios */
// API client do painel admin para PatientPortalSetting (Sprint G).
// Endpoints expostos no plugin patient_portal em
// /api/v1/accounts/:account_id/patient_portal/setting{,/apply_preset}.
import ApiClient from '../ApiClient';

class PatientPortalSettingsAPI extends ApiClient {
  constructor() {
    super('patient_portal/setting', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  update(setting) {
    return axios.patch(this.url, { setting });
  }

  applyPreset(presetKey) {
    return axios.post(`${this.url}/apply_preset`, { preset_key: presetKey });
  }
}

export default new PatientPortalSettingsAPI();
