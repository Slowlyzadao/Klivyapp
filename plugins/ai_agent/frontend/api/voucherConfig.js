/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Config de LANÇAMENTO por voucher POR CONTA. Recurso singular.
// { enabled: bool, triggers: [String] } — triggers são os textos do QR.
class AiAgentVoucherConfig extends ApiClient {
  constructor() {
    super('ai_agent/voucher_config', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update({ enabled, triggers }) {
    return axios.patch(this.url, { voucher_config: { enabled, triggers } });
  }
}

export default new AiAgentVoucherConfig();
