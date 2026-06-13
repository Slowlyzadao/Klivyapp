// Composable pra carregar e mutar SignatureRequest associados a um
// signable (Document ou ConsentRecord) específico. Não usa store global
// porque a lista é fortemente local ao componente que abre o modal.

import { ref, computed } from 'vue';
import { signatureRequestsApi } from '../api/signatureRequests';

export function useSignatureRequests(signableType, signableId) {
  const requests = ref([]);
  const loading = ref(false);
  const error = ref(null);

  const activeRequest = computed(() => {
    // Mostra o request mais recente que ainda não terminou (in-progress).
    // Se todos terminaram, devolve o último.
    return (
      requests.value.find(r => !r.terminal) ||
      requests.value[0] ||
      null
    );
  });

  const fetchAll = async () => {
    loading.value = true;
    error.value = null;
    try {
      const { data } = await signatureRequestsApi.list({
        signableType,
        signableId,
      });
      requests.value = data.data || [];
    } catch (e) {
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  };

  const sendForSignature = async payload => {
    const { data } = await signatureRequestsApi.create({
      signable_type: signableType,
      signable_id: signableId,
      ...payload,
    });
    requests.value = [data.data, ...requests.value];
    return data.data;
  };

  const cancel = async (id, reason) => {
    const { data } = await signatureRequestsApi.cancel(id, { reason });
    upsert(data.data);
    return data.data;
  };

  const resend = async id => {
    const { data } = await signatureRequestsApi.resend(id);
    upsert(data.data);
    return data.data;
  };

  const refreshStatus = async id => {
    const { data } = await signatureRequestsApi.refreshStatus(id);
    upsert(data.data);
    return data.data;
  };

  const upsert = (updated) => {
    const idx = requests.value.findIndex(r => r.id === updated.id);
    if (idx >= 0) requests.value.splice(idx, 1, updated);
    else requests.value = [updated, ...requests.value];
  };

  return {
    requests,
    activeRequest,
    loading,
    error,
    fetchAll,
    sendForSignature,
    cancel,
    resend,
    refreshStatus,
  };
}
