import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';

export function useSettingsServices(store) {
  const serviceModal = ref(false);
  const serviceDraft = ref(null);
  const serviceDeleteId = ref(null);
  const serviceDeleteName = ref('');
  const serviceDeleteConfirm = ref(false);
  const serviceSaving = ref(false);
  const showColorPicker = ref(false);

  // Paleta de cores para os serviços (migrado do data original)
  const serviceColors = ref([
    '#3b82f6', // azul
    '#22c55e', // verde
    '#f59e0b', // amarelo
    '#ef4444', // vermelho
    '#a855f7', // roxo
    '#ec4899', // rosa
    '#14b8a6', // teal
    '#f97316', // laranja
    '#6366f1', // indigo
    '#64748b', // slate
  ]);

  const agendaServices = computed(() => {
    return store.getters['agendaServices/allServices'] || [];
  });

  const agendaServicesLoading = computed(() => {
    return store.getters['agendaServices/getUIFlags'].isFetching;
  });

  const openServiceModal = (service = null) => {
    if (service) {
      serviceDraft.value = { ...service };
    } else {
      serviceDraft.value = {
        name: '',
        duration_minutes: 60,
        price: 0,
        requires_room: false,
        color: '#3b82f6',
      };
    }
    serviceModal.value = true;
  };

  const closeServiceModal = () => {
    serviceModal.value = false;
    serviceDraft.value = null;
    showColorPicker.value = false;
  };

  const saveService = async () => {
    if (!serviceDraft.value) return;
    if (!serviceDraft.value.name?.trim()) return;
    serviceSaving.value = true;
    try {
      if (serviceDraft.value.id) {
        const { id, ...data } = serviceDraft.value;
        await store.dispatch('agendaServices/update', { id, ...data });
        useAlert('Serviço atualizado com sucesso!');
      } else {
        await store.dispatch('agendaServices/create', serviceDraft.value);
        useAlert('Serviço criado com sucesso!');
      }
      closeServiceModal();
    } catch (e) {
      console.error('[SettingsServices] Falha ao salvar:', e);
      useAlert('Falha ao salvar o serviço.');
    } finally {
      serviceSaving.value = false;
    }
  };

  const confirmDeleteService = (service) => {
    serviceDeleteId.value = service.id;
    serviceDeleteName.value = service.name;
    serviceDeleteConfirm.value = true;
  };

  const cancelDeleteService = () => {
    serviceDeleteId.value = null;
    serviceDeleteName.value = '';
    serviceDeleteConfirm.value = false;
  };

  const deleteService = async () => {
    if (!serviceDeleteId.value) return;
    try {
      await store.dispatch('agendaServices/delete', serviceDeleteId.value);
      useAlert('Serviço excluído.');
      cancelDeleteService();
    } catch (e) {
      useAlert('Falha ao excluir o serviço.');
    }
  };

  const formatPrice = (value) => {
    if (value === null || value === undefined || value === '') return '—';
    const num = parseFloat(value);
    if (isNaN(num)) return '—';
    return num.toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    });
  };

  const formatDuration = (minutes) => {
    if (!minutes) return '—';
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h === 0) return `${m}min`;
    if (m === 0) return `${h}h`;
    return `${h}h ${m}min`;
  };

  return {
    serviceModal,
    serviceDraft,
    serviceDeleteId,
    serviceDeleteName,
    serviceDeleteConfirm,
    serviceSaving,
    showColorPicker,
    serviceColors,
    agendaServices,
    agendaServicesLoading,
    openServiceModal,
    closeServiceModal,
    saveService,
    confirmDeleteService,
    cancelDeleteService,
    deleteService,
    formatPrice,
    formatDuration,
  };
}
