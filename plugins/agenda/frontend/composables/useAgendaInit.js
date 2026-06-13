import { watch } from 'vue';
import { startOfWeek, endOfWeek, startOfMonth, addDays, addMinutes } from 'date-fns';
import AgendaSettingsAPI from '@plugins/agenda/frontend/api/agendaSettings';
import AgendaCustomAttributesAPI from '@plugins/agenda/frontend/api/agendaCustomAttributes';
import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';

const REFETCH_DEBOUNCE_MS = 150;
// Atraso após o fetch da janela atual para disparar pre-fetch da próxima/anterior.
// Curto o suficiente para que clicks rápidos no prev/next encontrem o cache pronto,
// longo o suficiente para que navegação compulsiva (vários cliques) não dispare
// pre-fetches que serão imediatamente substituídos.
const PREFETCH_DELAY_MS = 800;
// Janela de deduplicação: um mesmo range não é re-disparado dentro deste TTL.
// Evita que onActivated + watcher + prefetch atrofiem o backend com requests
// repetidas para o mesmo intervalo. ETag já cobre o custo de bytes — isso aqui
// só elimina round-trips desnecessários.
const FETCH_DEDUPE_TTL_MS = 30_000;

// Calcula a janela [start, end) que cobre exatamente o que o usuário está vendo.
// Pequeno padding (1 minuto) em cada borda para que eventos visíveis no canto da
// grade nunca sejam clipados por arredondamento de timezone.
function computeRange(currentDate, viewMode) {
  let start;
  let end;

  if (viewMode === 'day') {
    start = new Date(currentDate);
    start.setHours(0, 0, 0, 0);
    end = new Date(currentDate);
    end.setHours(23, 59, 59, 999);
  } else if (viewMode === 'week') {
    start = startOfWeek(currentDate, { weekStartsOn: 0 });
    end = endOfWeek(currentDate, { weekStartsOn: 0 });
  } else {
    // Month view renderiza grade de 6 semanas a partir do início da semana
    // que contém o dia 1, exatamente como `calendarWeeks` em useAgenda.js.
    const firstDay = startOfMonth(currentDate);
    start = startOfWeek(firstDay, { weekStartsOn: 0 });
    end = addDays(start, 42);
    end.setHours(23, 59, 59, 999);
  }

  return {
    startsAt: addMinutes(start, -1).toISOString(),
    endsAt: addMinutes(end, 1).toISOString(),
  };
}

// Fallback simples caso o navegador não exponha requestIdleCallback (Safari ainda
// não tem em algumas versões). 250ms é tempo suficiente para a request "principal"
// começar antes do pre-fetch competir por largura de banda.
function runIdle(cb) {
  if (typeof window !== 'undefined' && typeof window.requestIdleCallback === 'function') {
    window.requestIdleCallback(cb, { timeout: 1500 });
  } else {
    setTimeout(cb, 250);
  }
}

export function useAgendaInit({ store, agendaState, checkQueryParams }) {
  let debounceTimer = null;
  let prefetchTimer = null;
  // O dashboard chama fetchInitialData tanto em onMounted quanto em onActivated
  // (necessário para suportar <KeepAlive> em rotas filhas). Sem este flag, a
  // primeira pintura disparava 2x a request inteira; agora apenas refrescamos
  // a janela visível nas re-ativações.
  let hasInitialized = false;
  // rangeKey ("startsAt|endsAt") → timestamp do último dispatch.
  const recentFetches = new Map();

  const dispatchRange = (startsAt, endsAt) => {
    if (!startsAt || !endsAt) return null;
    const key = `${startsAt}|${endsAt}`;
    const last = recentFetches.get(key);
    if (last && Date.now() - last < FETCH_DEDUPE_TTL_MS) return null;
    recentFetches.set(key, Date.now());
    return store.dispatch('agendaEvents/fetchByRange', { startsAt, endsAt });
  };

  const fetchEventsForView = () => {
    // Year View consome endpoint agregado (year_stats), não o de eventos
    // crus — fetchByRange estouraria INDEX_MAX_RESULTS pra ~1k+ eventos/ano
    // e ainda assim faltaria o breakdown por status que o heatmap precisa.
    if (agendaState.viewMode === 'year') {
      return store.dispatch('agendaEvents/fetchYearStats', {
        year: agendaState.currentDate.getFullYear(),
      });
    }
    const { startsAt, endsAt } = computeRange(
      agendaState.currentDate,
      agendaState.viewMode
    );
    return dispatchRange(startsAt, endsAt);
  };

  // Pre-fetch silencioso da semana/dia anterior e próximo. Roda em idle e usa
  // dedupe — o usuário sente clique em prev/next como "instantâneo" porque o
  // store já contém os eventos quando o watcher disparar a request.
  const prefetchAdjacent = () => {
    const mode = agendaState.viewMode;
    // Year View: pre-fetch dos anos vizinhos seria 2 requests de payload
    // agregado (~365 dias × ~8 colunas de status cada). Pequeno e barato,
    // mas raramente compensa — usuário tipicamente fica num ano só.
    // Skip por hora; revisitar se telemetria mostrar navegação frequente.
    if (mode === 'year') return;
    if (mode === 'month') return; // grade de 6 semanas já cobre vizinhança ampla

    const stepDays = mode === 'day' ? 1 : 7;
    const baseDate = agendaState.currentDate;

    const prevDate = new Date(baseDate);
    prevDate.setDate(prevDate.getDate() - stepDays);
    const nextDate = new Date(baseDate);
    nextDate.setDate(nextDate.getDate() + stepDays);

    runIdle(() => {
      const prev = computeRange(prevDate, mode);
      const next = computeRange(nextDate, mode);
      dispatchRange(prev.startsAt, prev.endsAt);
      dispatchRange(next.startsAt, next.endsAt);
    });
  };

  const scheduleFetch = () => {
    clearTimeout(debounceTimer);
    clearTimeout(prefetchTimer);
    debounceTimer = setTimeout(() => {
      fetchEventsForView();
      prefetchTimer = setTimeout(prefetchAdjacent, PREFETCH_DELAY_MS);
    }, REFETCH_DEBOUNCE_MS);
  };

  const fetchInitialData = async () => {
    if (hasInitialized) {
      // Re-ativação: dados estáticos (agentes, settings, custom attrs) já estão
      // carregados; só precisamos atualizar os eventos da janela atual.
      fetchEventsForView();
      clearTimeout(prefetchTimer);
      prefetchTimer = setTimeout(prefetchAdjacent, PREFETCH_DELAY_MS);
      if (checkQueryParams) checkQueryParams();
      return;
    }
    hasInitialized = true;

    // Caminho crítico — só o necessário para renderizar a grade
    store.dispatch('agents/get');
    store.dispatch('agendaServices/fetch');
    store.dispatch('agendaCategories/fetch');
    fetchEventsForView();
    waitingListStore.fetchAll();

    // NÃO dispatchar `contacts/get` aqui. A action commita `CLEAR_CONTACTS`
    // antes de repopular apenas a primeira página (pageSize=15), zerando
    // `records` no store global de contatos. Isso quebra reativamente
    // qualquer componente que dependa do registro completo (avatars da
    // sidebar de Conversas, painel direito do contato selecionado,
    // ContactInfo.vue → watch `contact.id` → `fetchContactableInbox` →
    // 404 se algum contato tem `contact_inbox` órfão). O modal da Agenda
    // (`AgendaEventModal.vue`) usa `ContactAPI` diretamente no picker —
    // não consome o getter `contacts/getContacts` —, então a pré-carga
    // aqui é puro dead weight com efeito colateral destrutivo.

    // Settings e custom attributes em paralelo
    try {
      const res = await AgendaSettingsAPI.get();
      agendaState.agendaSettingsData = res.data;
    } catch {
      // ignore
    }

    try {
      const res = await AgendaCustomAttributesAPI.getAll();
      agendaState.customAttributesConfig = res.data || [];
    } catch {
      // ignore
    }

    if (checkQueryParams) {
      checkQueryParams();
    }

    // Pre-fetch das janelas adjacentes em idle, depois que o caminho crítico
    // terminou de pintar.
    prefetchTimer = setTimeout(prefetchAdjacent, PREFETCH_DELAY_MS);
  };

  // Refetch ao trocar semana/dia/mês ou ao alternar o modo de visualização.
  // Debounced: clicar prev/next rapidamente dispara apenas a última requisição.
  watch(
    () => [agendaState.currentDate, agendaState.viewMode],
    scheduleFetch
  );

  return {
    fetchInitialData,
    fetchEventsForView,
  };
}
