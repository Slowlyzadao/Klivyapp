// Cliente das APIs de documentos.
import { http } from './http';

const BASE = '/api/v1/patient_portal/documents';

export const documentsApi = {
  list: () => http.get(BASE),
  get:  (id) => http.get(`${BASE}/${id}`),
  // O download é uma navegação real do navegador (precisa do JWT no header).
  // O método baixa via fetch + cria Blob → URL.createObjectURL pra abrir.
  download: async (id, filename) => {
    const { useAuthStore } = await import('../store/auth');
    const token = useAuthStore().jwt;
    const res = await fetch(`${BASE}/${id}/download`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (!res.ok) throw new Error(`Falha no download (${res.status})`);
    const blob = await res.blob();
    const url  = URL.createObjectURL(blob);
    // Abre em nova aba — paciente pode salvar do viewer do navegador.
    window.open(url, '_blank', 'noopener,noreferrer');
    // Cleanup depois de um tempo
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }
};
