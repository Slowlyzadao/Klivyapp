import { ref, computed } from 'vue';
import { teleconsultasApi } from '../api/teleconsultas';

// Sprint L — Composable de listagem de teleconsultas (paginada + filtros).
// Cada filtro mudado dispara fetch — paginação reseta pra page=1.
export function useTeleconsultaList(initialTab = 'upcoming') {
  const tab = ref(initialTab);
  const items = ref([]);
  const page = ref(1);
  const perPage = ref(20);
  const hasMore = ref(false);
  const isLoading = ref(false);
  const error = ref(null);
  const filters = ref({ professionalId: null, dateFrom: null, dateTo: null });

  const isEmpty = computed(() => !isLoading.value && items.value.length === 0);
  const counts = ref({
    upcoming: null,
    in_progress: null,
    finished: null,
    no_show: null,
  });

  const fetchCounts = async () => {
    try {
      const { data } = await teleconsultasApi.counts();
      counts.value = { ...counts.value, ...(data?.data || {}) };
    } catch {
      // Counts são meramente cosméticos — falha silenciosa, mantém null
      // (UI esconde o badge quando não há valor).
    }
  };

  // Sequência monotônica de requests pra resolver race quando troca de
  // tab rapidamente (audit #25). Se o usuário clica Tab A → Tab B antes
  // de Tab A responder, queremos garantir que Tab A não sobrescreva os
  // resultados de Tab B (last-writer-wins clássico de UI assíncrona).
  // Cada fetch captura um id local; só aplica resultado se ainda é o
  // último request em curso.
  let requestSeq = 0;

  const fetch = async (opts = {}) => {
    if (opts.reset) {
      page.value = 1;
      items.value = [];
    }
    const myReq = ++requestSeq;
    isLoading.value = true;
    error.value = null;
    try {
      const { data } = await teleconsultasApi.list({
        tab: tab.value,
        page: page.value,
        perPage: perPage.value,
        ...filters.value,
      });
      // Resposta tardia de tab antiga — descarta silenciosamente.
      if (myReq !== requestSeq) return;

      if (opts.reset) {
        items.value = data.data;
      } else {
        items.value = [...items.value, ...data.data];
      }
      hasMore.value = data.meta?.has_more ?? false;
    } catch (e) {
      if (myReq !== requestSeq) return;
      error.value = e?.response?.data?.error || e.message;
    } finally {
      if (myReq === requestSeq) isLoading.value = false;
    }
  };

  const setTab = async newTab => {
    tab.value = newTab;
    await fetch({ reset: true });
  };

  const applyFilters = async newFilters => {
    filters.value = { ...filters.value, ...newFilters };
    await fetch({ reset: true });
  };

  const loadMore = async () => {
    if (!hasMore.value || isLoading.value) return;
    page.value += 1;
    await fetch();
  };

  // Total de páginas conhecido a partir do `counts[tab]`. Retorna `null`
  // enquanto o backend não respondeu — UI esconde a paginação nesse caso.
  const totalPages = computed(() => {
    const total = counts.value?.[tab.value];
    if (typeof total !== 'number' || total <= 0) return null;
    return Math.max(1, Math.ceil(total / perPage.value));
  });

  // Pula para a página N (1-based). Faz fetch substituindo a lista (não
  // concatena como o loadMore). Clampa para o range [1, totalPages].
  const goToPage = async target => {
    const next = Math.max(1, Math.floor(Number(target) || 1));
    const clamped = totalPages.value ? Math.min(next, totalPages.value) : next;
    if (clamped === page.value) return;
    page.value = clamped;
    items.value = [];
    await fetch();
  };

  return {
    tab,
    items,
    page,
    perPage,
    totalPages,
    isLoading,
    isEmpty,
    error,
    hasMore,
    filters,
    counts,
    fetch,
    fetchCounts,
    setTab,
    applyFilters,
    loadMore,
    goToPage,
  };
}
