import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import ServicesAPI from '@plugins/agenda/frontend/api/agendaServices';

export function useSettingsServices(store) {
  const serviceModal = ref(false);
  const serviceDraft = ref(null);
  const serviceDeleteId = ref(null);
  const serviceDeleteName = ref('');
  const serviceDeleteConfirm = ref(false);
  const serviceSaving = ref(false);
  const showColorPicker = ref(false);
  // PR #7 da auditoria: contadores carregados quando o usuário clica em excluir.
  // `null` = ainda carregando ou nunca pediu; objeto = stats prontos.
  const serviceDeleteStats = ref(null);
  const serviceDeleteStatsLoading = ref(false);

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

  // Extrai a mensagem real do erro axios do backend (`{ error: "..." }` em 422).
  // Definida cedo no escopo porque é usada pelas funções paginadas abaixo
  // (consts não sofrem hoisting; precisa estar antes do uso).
  const extractBackendMessage = (e, fallback) => {
    return (
      e?.response?.data?.error ||
      e?.response?.data?.message ||
      e?.message ||
      fallback
    );
  };

  // ─── PR de UI overhaul (2026-05-14): estado paginado + busca + cleanup ────
  // Estado local da aba Settings — independente do store global que alimenta
  // calendário/sidebar. Settings tem milhares de serviços em contas grandes,
  // não cabe carregar tudo de uma vez no DOM.
  const pageServices = ref([]);
  const pageMeta = ref({ current_page: 1, per_page: 10, total_count: 0, total_pages: 0 });
  const pageLoading = ref(false);
  const searchQuery = ref('');
  const cleanupPreview = ref(null); // { count, services } | null
  const cleanupRunning = ref(false);
  // Simplificação (2026-05-14): toda exclusão é hard-delete agora — sem
  // distinção entre soft/hard-delete na UI. O modal por linha confirma com
  // contagem de uso; "Limpar sem uso" inclui todos os serviços sem vínculo
  // (ativos ou já arquivados em produção legada).

  // Debounce simples pra busca não bombardear o backend a cada tecla.
  let searchTimer = null;

  const fetchPage = async (page = 1) => {
    pageLoading.value = true;
    try {
      const { data } = await ServicesAPI.getPaginated({
        page,
        perPage: pageMeta.value.per_page || 10,
        q: searchQuery.value.trim(),
      });
      pageServices.value = data.services || [];
      pageMeta.value = data.meta || pageMeta.value;
    } catch (e) {
      console.error('[SettingsServices] Falha ao buscar página:', e);
      useAlert(extractBackendMessage(e, 'Falha ao carregar serviços.'));
    } finally {
      pageLoading.value = false;
    }
  };

  const refreshCurrentPage = () => fetchPage(pageMeta.value.current_page || 1);

  const goToPage = (n) => {
    const target = Math.max(1, Math.min(n, pageMeta.value.total_pages || 1));
    if (target === pageMeta.value.current_page) return;
    fetchPage(target);
  };

  // Adicionado para integração com o componente global <Pagination> que
  // emite `update:per-page` quando o usuário troca o tamanho. Reseta para
  // página 1 — comportamento esperado para evitar ficar fora de range.
  const setPerPage = (n) => {
    const next = Number(n) || 10;
    if (next === pageMeta.value.per_page) return;
    pageMeta.value.per_page = next;
    fetchPage(1);
  };

  const onSearchChange = (value) => {
    searchQuery.value = value;
    clearTimeout(searchTimer);
    // 300ms debounce. Reseta para a página 1 em toda busca nova.
    searchTimer = setTimeout(() => fetchPage(1), 300);
  };

  const loadCleanupPreview = async () => {
    try {
      const { data } = await ServicesAPI.cleanupUnusedPreview();
      cleanupPreview.value = data;
      return data;
    } catch (e) {
      console.error('[SettingsServices] Falha ao prever limpeza:', e);
      useAlert(extractBackendMessage(e, 'Falha ao verificar serviços sem uso.'));
      return null;
    }
  };

  // ─── PR #9: Drag-and-drop reorder ─────────────────────────────────────
  // Estado leve: índices na lista atual (`pageServices`) — não o ID do
  // serviço — pra simplificar o swap visual durante o drag. Resolve em ID
  // só na hora de persistir.
  const dragState = ref({ srcIndex: null, overIndex: null });
  const reorderSaving = ref(false);

  const onDragStart = (event, idx) => {
    // Bloqueia drag quando busca ativa: reordenar uma lista filtrada
    // confundiria a relação com os slots de position no banco.
    if (searchQuery.value.trim()) {
      event.preventDefault();
      return;
    }
    dragState.value = { srcIndex: idx, overIndex: idx };
    // Required pelo Firefox para o drag começar. effectAllowed dá feedback do cursor.
    event.dataTransfer.effectAllowed = 'move';
    try {
      event.dataTransfer.setData('text/plain', String(idx));
    } catch (_) {
      // IE11 não suporta — ignora; drag funciona sem.
    }
  };

  const onDragOver = (idx) => {
    if (dragState.value.srcIndex === null) return;
    if (dragState.value.overIndex !== idx) {
      dragState.value.overIndex = idx;
    }
  };

  const onDragEnd = () => {
    dragState.value = { srcIndex: null, overIndex: null };
  };

  const onDrop = async (targetIdx) => {
    const { srcIndex } = dragState.value;
    dragState.value = { srcIndex: null, overIndex: null };
    if (srcIndex === null || srcIndex === targetIdx) return;

    // Reorder otimista local. Revert se a API falhar.
    const original = [...pageServices.value];
    const moved = original[srcIndex];
    const optimistic = [...original];
    optimistic.splice(srcIndex, 1);
    optimistic.splice(targetIdx, 0, moved);
    pageServices.value = optimistic;

    reorderSaving.value = true;
    try {
      const ids = optimistic.map((s) => s.id);
      await ServicesAPI.reorder(ids);
      // Sync do store global para o calendário/sidebar refletirem a nova ordem.
      store.dispatch('agendaServices/fetch').catch(() => {});
    } catch (e) {
      console.error('[SettingsServices] Falha no drag-reorder:', e);
      useAlert(extractBackendMessage(e, 'Falha ao salvar nova ordem.'));
      pageServices.value = original;
    } finally {
      reorderSaving.value = false;
    }
  };

  const runCleanupUnused = async () => {
    cleanupRunning.value = true;
    try {
      const { data } = await ServicesAPI.cleanupUnused();
      useAlert(
        data.cleaned_count > 0
          ? `${data.cleaned_count} serviço(s) sem uso foram excluídos permanentemente.`
          : 'Nenhum serviço sem uso encontrado.'
      );
      cleanupPreview.value = null;
      await refreshCurrentPage();
      // Refetcha também a lista global do store (calendário/sidebar) pra
      // refletir os serviços excluídos.
      store.dispatch('agendaServices/fetch').catch(() => {});
    } catch (e) {
      console.error('[SettingsServices] Falha no cleanup:', e);
      useAlert(extractBackendMessage(e, 'Falha ao excluir serviços sem uso.'));
    } finally {
      cleanupRunning.value = false;
    }
  };


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
      // PR de UI overhaul: refetcha a página atual para refletir o item
      // novo/atualizado COM os contadores corretos (vêm da subquery do backend).
      refreshCurrentPage();
    } catch (e) {
      console.error('[SettingsServices] Falha ao salvar:', e);
      useAlert(extractBackendMessage(e, 'Falha ao salvar o serviço.'));
    } finally {
      serviceSaving.value = false;
    }
  };

  const confirmDeleteService = async (service) => {
    serviceDeleteId.value = service.id;
    serviceDeleteName.value = service.name;
    serviceDeleteConfirm.value = true;
    serviceDeleteStats.value = null;
    serviceDeleteStatsLoading.value = true;
    try {
      // PR #7 da auditoria: busca contadores ANTES de mostrar a confirmação
      // pra que o operador decida com base em dados reais, não no escuro.
      const { data } = await ServicesAPI.usageStats(service.id);
      serviceDeleteStats.value = data;
    } catch (e) {
      console.error('[SettingsServices] Falha ao buscar usage stats:', e);
      // Sem stats, mostra modal mesmo assim — fallback para texto genérico.
      serviceDeleteStats.value = { agenda_events_count: null, treatment_items_count: null };
    } finally {
      serviceDeleteStatsLoading.value = false;
    }
  };

  const cancelDeleteService = () => {
    serviceDeleteId.value = null;
    serviceDeleteName.value = '';
    serviceDeleteConfirm.value = false;
    serviceDeleteStats.value = null;
    serviceDeleteStatsLoading.value = false;
  };

  const deleteService = async () => {
    if (!serviceDeleteId.value) return;
    try {
      await store.dispatch('agendaServices/delete', serviceDeleteId.value);
      useAlert('Serviço excluído.');
      cancelDeleteService();
      refreshCurrentPage();
    } catch (e) {
      console.error('[SettingsServices] Falha ao excluir:', e);
      useAlert(extractBackendMessage(e, 'Falha ao excluir o serviço.'));
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
    serviceDeleteStats,
    serviceDeleteStatsLoading,
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
    // PR de UI overhaul (2026-05-14):
    pageServices,
    pageMeta,
    pageLoading,
    searchQuery,
    cleanupPreview,
    cleanupRunning,
    fetchPage,
    refreshCurrentPage,
    goToPage,
    setPerPage,
    onSearchChange,
    loadCleanupPreview,
    runCleanupUnused,
    // PR #9 — drag-and-drop:
    dragState,
    reorderSaving,
    onDragStart,
    onDragOver,
    onDragEnd,
    onDrop,
  };
}
