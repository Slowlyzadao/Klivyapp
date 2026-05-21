// Cliente das APIs financeiras do paciente (read-only MVP).
import { http } from './http';

const BASE = '/api/v1/patient_portal/financial';

export const financialApi = {
  summary:          ()           => http.get(`${BASE}/summary`),
  installments:     (scope)      => http.get(`${BASE}/installments${scope ? `?scope=${scope}` : ''}`),
  installment:      (id)         => http.get(`${BASE}/installments/${id}`),

  // Download de comprovante via fetch + blob (mesmo padrão de documents).
  proof: async (id) => {
    const { useAuthStore } = await import('../store/auth');
    const token = useAuthStore().jwt;
    const res = await fetch(`${BASE}/installments/${id}/proof`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (!res.ok) throw new Error(`Falha no download (${res.status})`);
    const blob = await res.blob();
    const url  = URL.createObjectURL(blob);
    window.open(url, '_blank', 'noopener,noreferrer');
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }
};
