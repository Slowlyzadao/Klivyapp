<script setup>
/**
 * AgendaYearView — visualização anual (heatmap) da agenda.
 *
 * Estratégia de dados:
 *   - 1 request agregada por ano via `agendaEvents/fetchYearStats`
 *   - watcher em `currentDate.getFullYear()` (não em currentDate inteira) →
 *     navegar entre meses do mesmo ano não dispara refetch
 *   - cache no store por (ano + userId)
 *
 * Performance:
 *   - useYearCalendar agrega totais/peak em pass único O(365)
 *   - dayCells é estrutura computed memoizada por mês — recomputa só quando
 *     ano ou byDay mudam
 *   - YearDayCell é puro/stateless — re-render só quando props mudam
 */
import { computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useYearCalendar } from '../composables/useYearCalendar.js';
import { MONTH_KEYS } from '../utils/agenda-constants.js';
import YearHeader from './year/YearHeader.vue';
import YearMonthCard from './year/YearMonthCard.vue';
import YearLegend from './year/YearLegend.vue';

const props = defineProps({
  currentDate: { type: Date, required: true },
  hiddenStatuses: { type: Array, default: () => [] },
  isDarkTheme: { type: Boolean, default: false },
  // Reusa o sistema de bloqueios do useAgenda (feriados, folgas, dias fechados).
  // Padrão sem-op = year view também funciona em contextos sem settings carregadas
  // (ex: primeira pintura antes do fetch de agendaSettings concluir).
  isDayBlocked: { type: Function, default: () => false },
  getDayBlockInfo: { type: Function, default: () => [] },
});

const emit = defineEmits(['view-day', 'view-month']);

const store = useStore();

const year = computed(() => props.currentDate.getFullYear());
const isFetching = computed(
  () => !!store.getters['agendaEvents/getUIFlags']?.isFetchingYearStats
);

const yearStatsRecord = computed(() => store.getters['agendaEvents/getYearStats'](year.value));
const byDay = computed(() => yearStatsRecord.value?.byDay || {});
const fetchError = computed(() => yearStatsRecord.value?.error || null);

const hiddenStatusesRef = computed(() => props.hiddenStatuses);

const {
  monthTotals,
  yearTotal,
  peakMonth,
  dayMax,
  colorBucket,
  getDay,
} = useYearCalendar({
  byDay,
  year,
  hiddenStatuses: hiddenStatusesRef,
});

// Hoje (para destacar a célula correspondente no heatmap)
const today = computed(() => {
  const now = new Date();
  return {
    year: now.getFullYear(),
    month: now.getMonth(),
    day: now.getDate(),
  };
});

// Dispara fetch quando o ano muda. O dispatch inicial é feito pelo
// useAgendaInit (watcher em viewMode/currentDate), mas duplicar aqui
// cobre o caso de re-mount com cache vazio sem regredir performance
// (dedup pela `force=false` no store).
function loadYear() {
  store.dispatch('agendaEvents/fetchYearStats', { year: year.value });
}

onMounted(loadYear);

watch(year, () => {
  loadYear();
});

const months = computed(() =>
  Array.from({ length: 12 }, (_, i) => ({
    index: i,
    key: MONTH_KEYS[i],
    total: monthTotals.value[i],
  }))
);

function onDayClick(dayObj) {
  emit('view-day', dayObj);
}

function onMonthClick(monthIndex) {
  emit('view-month', { year: year.value, month: monthIndex });
}
</script>

<template>
  <div class="year-view" :class="{ 'year-view--dark': isDarkTheme }">
    <YearHeader
      :year="year"
      :year-total="yearTotal"
      :peak-month="peakMonth"
      :month-totals="monthTotals"
      :is-loading="!yearStatsRecord && isFetching"
    />

    <div v-if="fetchError" class="year-view__error" role="alert">
      <i class="i-lucide-alert-triangle" />
      <span>
        Não foi possível carregar os dados anuais (erro {{ fetchError }}).
        Tente recarregar a página.
      </span>
    </div>

    <YearLegend :is-loading="!yearStatsRecord && isFetching" />

    <div class="year-view__grid" role="list">
      <YearMonthCard
        v-for="month in months"
        :key="month.index"
        :year="year"
        :month-index="month.index"
        :month-key="month.key"
        :total="month.total"
        :today="today"
        :color-bucket="colorBucket"
        :get-day="getDay"
        :is-day-blocked="isDayBlocked"
        :get-day-block-info="getDayBlockInfo"
        @month-click="onMonthClick(month.index)"
        @day-click="onDayClick"
      />
    </div>
  </div>
</template>
