<script setup>
// Página de lista de teleconsultas (clínica).
// Layout em grid de cards com tabs superiores (badge de contagem + ponto
// "ao vivo" pulsante na aba "Em andamento" quando ativa). Paginação
// numerada aparece quando há contagem total conhecida.
// Estilos vivem em `@plugins/telemed/frontend/styles/teleconsulta-index.scss`.
import '@plugins/telemed/frontend/styles/teleconsulta-index.scss';

import { onMounted, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useTeleconsultaList } from '../../composables/useTeleconsultaList';
import TeleconsultaCard from './TeleconsultaCard.vue';
import TeleconsultaScheduleNewCard from './TeleconsultaScheduleNewCard.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';

const router = useRouter();
const {
  tab, items, page, perPage, isLoading, isEmpty, error, counts,
  setTab, fetch, fetchCounts, goToPage,
} = useTeleconsultaList('upcoming');

const TABS = [
  { key: 'upcoming',    label: 'Próximas' },
  { key: 'in_progress', label: 'Em andamento' },
  { key: 'finished',    label: 'Finalizadas' },
  { key: 'no_show',     label: 'Sem comparecimento' },
];

onMounted(() => {
  fetch({ reset: true });
  fetchCounts();
});

const tabCount = key => {
  const fromApi = counts.value?.[key];
  if (typeof fromApi === 'number') return fromApi;
  if (tab.value === key) return items.value.length;
  return null;
};

const goToDetail = item => {
  router.push({ name: 'teleconsulta_detail', params: { eventId: item.id } });
};

const enterRoom = item => {
  const url = router.resolve({
    name: 'agenda_telemed_room',
    params: { eventId: item.id },
  }).href;
  window.open(url, '_blank', 'noopener');
};

// "Preparar" / "Ver Resumo" levam ao detalhe por enquanto — as telas
// dedicadas (preparo + resumo modal) serão definidas em sprints futuras.
const prepare = item => goToDetail(item);
const openSummary = item => {
  router.push({
    name: 'teleconsulta_detail',
    params: { eventId: item.id },
    query: { focus: 'summary' },
  });
};

const scheduleNew = () => {
  // Hook para o futuro fluxo de criação de teleconsulta. Por ora
  // direciona à agenda — alinhar com o produto na próxima tela.
  router.push({ name: 'agenda_dashboard_index' });
};

const liveCount = computed(() => counts.value?.in_progress ?? 0);

// Total de itens da aba atual (vem do endpoint /counts). Alimenta a paginação
// padrão do beclinic_core; 0 esconde a paginação.
const totalCount = computed(() => counts.value?.[tab.value] || 0);
</script>

<template>
  <div class="tc-page">
    <header class="tc-header">
      <div class="tc-header__row">
        <div class="tc-header__titles">
          <h1 class="tc-title">Teleconsultas</h1>
          <p class="tc-subtitle">
            Gerencie suas consultas remotas de forma simples e segura
          </p>
        </div>

        <div class="tc-header__actions">
          <BeclinicButton
            variant="solid"
            color="blue"
            icon="i-lucide-plus"
            label="Nova Consulta"
            @click="scheduleNew"
          />
        </div>
      </div>
    </header>

    <nav class="tc-tabs" role="tablist">
      <button
        v-for="t in TABS"
        :key="t.key"
        type="button"
        role="tab"
        :aria-selected="tab === t.key"
        :class="['tc-tab', { 'is-active': tab === t.key }]"
        @click="setTab(t.key)"
      >
        <span>{{ t.label }}</span>
        <span
          v-if="t.key === 'in_progress' && tab === 'in_progress' && liveCount > 0"
          class="tc-tab-live-dot"
          aria-hidden="true"
        />
        <span v-if="tabCount(t.key) !== null" class="tc-tab-count">
          {{ tabCount(t.key) }}
        </span>
      </button>
    </nav>

    <section class="tc-grid">
      <!-- Skeleton (audit Fase 3) — 3 cards fantasma enquanto carrega;
           dá feedback de "algo está vindo" sem ainda mostrar dados,
           reduz percepção de latência vs spinner texto-only. -->
      <template v-if="isLoading && items.length === 0">
        <div
          v-for="n in 3"
          :key="`skeleton-${n}`"
          class="tc-skeleton"
          aria-hidden="true"
        >
          <div class="tc-skeleton__avatar" />
          <div class="tc-skeleton__lines">
            <div class="tc-skeleton__line tc-skeleton__line--title" />
            <div class="tc-skeleton__line tc-skeleton__line--subtitle" />
            <div class="tc-skeleton__line tc-skeleton__line--meta" />
          </div>
        </div>
      </template>
      <div v-else-if="error" class="tc-state tc-state--error">
        Erro ao carregar: {{ error }}
      </div>
      <template v-else>
        <TeleconsultaCard
          v-for="item in items"
          :key="item.id"
          :item="item"
          @open="goToDetail(item)"
          @prepare="prepare(item)"
          @enter-room="enterRoom(item)"
          @summary="openSummary(item)"
        />

        <div v-if="isEmpty" class="tc-state">
          Nenhuma teleconsulta nesta categoria.
        </div>

        <TeleconsultaScheduleNewCard
          v-if="tab === 'upcoming' || tab === 'in_progress'"
          @click="scheduleNew"
        />
      </template>
    </section>

    <Pagination
      :current-page="page"
      :per-page="perPage"
      :total-count="totalCount"
      item-label="teleconsultas"
      :show-per-page="false"
      @update:current-page="goToPage"
    />
  </div>
</template>
