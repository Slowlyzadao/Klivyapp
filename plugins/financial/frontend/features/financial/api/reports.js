/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class FinancialReportsAPI extends ApiClient {
  constructor() {
    super('financial/reports', { accountScoped: true });
  }

  cashFlow(params = {}) {
    return axios.get(`${this.url}/cash_flow`, { params });
  }

  monthlySummary(months = 6) {
    return axios.get(`${this.url}/monthly_summary`, { params: { months } });
  }

  dre(params = {}) {
    return axios.get(`${this.url}/dre`, { params });
  }

  commissions(params = {}) {
    return axios.get(`${this.url}/commissions`, { params });
  }

  insurance(params = {}) {
    return axios.get(`${this.url}/insurance`, { params });
  }

  averageTicket(params = {}) {
    return axios.get(`${this.url}/average_ticket`, { params });
  }
}

/** Opens a CSV download tab for any financial report endpoint */
export function downloadReportCSV(endpoint, params = {}) {
  const query = new URLSearchParams({ ...params, format: 'csv' }).toString();
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;
  window.open(
    `/api/v1/accounts/${accountId}/financial/reports/${endpoint}?${query}`,
    '_blank'
  );
}

export default new FinancialReportsAPI();
