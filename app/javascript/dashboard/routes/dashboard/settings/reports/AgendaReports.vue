<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import AgendaReportsAPI from '@plugins/agenda/frontend/api/agendaReports';
import ReportHeader from './components/ReportHeader.vue';

const { t } = useI18n();
const store = useStore();

function formatDateISO(date) {
  return date.toISOString().split('T')[0];
}

const isLoading = ref(false);
const reportData = ref(null);
const selectedAgent = ref(null);

const DATE_PRESETS = [
  { key: 'today', i18nKey: 'AGENDA_REPORTS.PRESETS.TODAY' },
  { key: 'yesterday', i18nKey: 'AGENDA_REPORTS.PRESETS.YESTERDAY' },
  { key: 'last_3_days', i18nKey: 'AGENDA_REPORTS.PRESETS.LAST_3_DAYS' },
  { key: 'last_7_days', i18nKey: 'AGENDA_REPORTS.PRESETS.LAST_7_DAYS' },
  { key: 'last_15_days', i18nKey: 'AGENDA_REPORTS.PRESETS.LAST_15_DAYS' },
  { key: 'last_30_days', i18nKey: 'AGENDA_REPORTS.PRESETS.LAST_30_DAYS' },
  { key: 'this_month', i18nKey: 'AGENDA_REPORTS.PRESETS.THIS_MONTH' },
];
const selectedPreset = ref('last_7_days');

const agents = computed(() => store.getters['agents/getAgents'] || []);

function getDateRange(preset) {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let from = today;

  switch (preset) {
    case 'today':
      from = today;
      break;
    case 'yesterday': {
      const d = new Date(today);
      d.setDate(d.getDate() - 1);
      return { since: formatDateISO(d), until: formatDateISO(d) };
    }
    case 'last_3_days': {
      const d = new Date(today);
      d.setDate(d.getDate() - 2);
      from = d;
      break;
    }
    case 'last_7_days': {
      const d = new Date(today);
      d.setDate(d.getDate() - 6);
      from = d;
      break;
    }
    case 'last_15_days': {
      const d = new Date(today);
      d.setDate(d.getDate() - 14);
      from = d;
      break;
    }
    case 'last_30_days': {
      const d = new Date(today);
      d.setDate(d.getDate() - 29);
      from = d;
      break;
    }
    case 'this_month':
      from = new Date(today.getFullYear(), today.getMonth(), 1);
      break;
    default:
      break;
  }

  return { since: formatDateISO(from), until: formatDateISO(today) };
}

const current = computed(() => reportData.value?.current || {});
const previous = computed(() => reportData.value?.previous || {});
const statusBreakdown = computed(
  () => reportData.value?.status_breakdown || {}
);
const dailyDistribution = computed(
  () => reportData.value?.daily_distribution || []
);
const agentPerformance = computed(
  () => reportData.value?.agent_performance || []
);

function getComparison(currentVal, previousVal) {
  if (previousVal === 0 && currentVal === 0) {
    return { pct: 0, direction: 'neutral' };
  }
  if (previousVal === 0) {
    return { pct: 100, direction: 'up' };
  }
  const pct = (((currentVal - previousVal) / previousVal) * 100).toFixed(1);
  if (pct > 0) return { pct, direction: 'up' };
  if (pct < 0) return { pct: Math.abs(pct), direction: 'down' };
  return { pct: 0, direction: 'neutral' };
}

const kpiCards = computed(() => [
  {
    key: 'total',
    i18nKey: 'AGENDA_REPORTS.KPI.SCHEDULED',
    value: current.value.total || 0,
    previousValue: previous.value.total || 0,
    icon: 'i-lucide-calendar-days',
    colorClass: 'kpi--blue',
  },
  {
    key: 'confirmed',
    i18nKey: 'AGENDA_REPORTS.KPI.CONFIRMED',
    value: current.value.confirmed || 0,
    previousValue: previous.value.confirmed || 0,
    icon: 'i-lucide-check-circle-2',
    colorClass: 'kpi--green',
  },
  {
    key: 'unconfirmed',
    i18nKey: 'AGENDA_REPORTS.KPI.PENDING',
    value: current.value.unconfirmed || 0,
    previousValue: previous.value.unconfirmed || 0,
    icon: 'i-lucide-clock',
    colorClass: 'kpi--amber',
  },
  {
    key: 'completed',
    i18nKey: 'AGENDA_REPORTS.KPI.COMPLETED',
    value: current.value.completed || 0,
    previousValue: previous.value.completed || 0,
    icon: 'i-lucide-user-check',
    colorClass: 'kpi--emerald',
  },
  {
    key: 'in_progress',
    i18nKey: 'AGENDA_REPORTS.KPI.IN_PROGRESS',
    value: current.value.in_progress || 0,
    previousValue: previous.value.in_progress || 0,
    icon: 'i-lucide-stethoscope',
    colorClass: 'kpi--cyan',
  },
  {
    key: 'arrived',
    i18nKey: 'AGENDA_REPORTS.KPI.WAITING',
    value: current.value.arrived || 0,
    previousValue: previous.value.arrived || 0,
    icon: 'i-lucide-armchair',
    colorClass: 'kpi--purple',
  },
  {
    key: 'no_show',
    i18nKey: 'AGENDA_REPORTS.KPI.NO_SHOW',
    value: current.value.no_show || 0,
    previousValue: previous.value.no_show || 0,
    icon: 'i-lucide-user-x',
    colorClass: 'kpi--red',
    invertComparison: true,
  },
  {
    key: 'cancelled',
    i18nKey: 'AGENDA_REPORTS.KPI.CANCELLED',
    value: current.value.cancelled || 0,
    previousValue: previous.value.cancelled || 0,
    icon: 'i-lucide-x-circle',
    colorClass: 'kpi--slate',
    invertComparison: true,
  },
]);

const rateCards = computed(() => [
  {
    key: 'occupancy_rate',
    i18nKey: 'AGENDA_REPORTS.RATES.OCCUPANCY',
    value: current.value.occupancy_rate || 0,
    previousValue: previous.value.occupancy_rate || 0,
    icon: 'i-lucide-gauge',
    colorClass: 'rate--blue',
  },
  {
    key: 'no_show_rate',
    i18nKey: 'AGENDA_REPORTS.RATES.NO_SHOW',
    value: current.value.no_show_rate || 0,
    previousValue: previous.value.no_show_rate || 0,
    icon: 'i-lucide-user-x',
    colorClass: 'rate--red',
    invertComparison: true,
  },
  {
    key: 'completion_rate',
    i18nKey: 'AGENDA_REPORTS.RATES.EFFICIENCY',
    value: current.value.completion_rate || 0,
    previousValue: previous.value.completion_rate || 0,
    icon: 'i-lucide-trending-up',
    colorClass: 'rate--emerald',
  },
]);

const maxDailyTotal = computed(() => {
  if (!dailyDistribution.value.length) return 1;
  return Math.max(...dailyDistribution.value.map(d => d.total), 1);
});

const statusItems = computed(() => {
  const items = [
    {
      key: 'scheduled',
      i18nKey: 'AGENDA_REPORTS.STATUS.SCHEDULED',
      color: '#3b82f6',
      count: statusBreakdown.value.scheduled || 0,
    },
    {
      key: 'confirmed',
      i18nKey: 'AGENDA_REPORTS.STATUS.CONFIRMED',
      color: '#22c55e',
      count: statusBreakdown.value.confirmed || 0,
    },
    {
      key: 'arrived',
      i18nKey: 'AGENDA_REPORTS.STATUS.ARRIVED',
      color: '#a855f7',
      count: statusBreakdown.value.arrived || 0,
    },
    {
      key: 'in_progress',
      i18nKey: 'AGENDA_REPORTS.STATUS.IN_PROGRESS',
      color: '#06b6d4',
      count: statusBreakdown.value.in_progress || 0,
    },
    {
      key: 'completed',
      i18nKey: 'AGENDA_REPORTS.STATUS.COMPLETED',
      color: '#10b981',
      count: statusBreakdown.value.completed || 0,
    },
    {
      key: 'no_show',
      i18nKey: 'AGENDA_REPORTS.STATUS.NO_SHOW',
      color: '#ef4444',
      count: statusBreakdown.value.no_show || 0,
    },
    {
      key: 'cancelled',
      i18nKey: 'AGENDA_REPORTS.STATUS.CANCELLED',
      color: '#64748b',
      count: statusBreakdown.value.cancelled || 0,
    },
  ];
  return items.filter(i => i.count > 0);
});

const statusTotal = computed(() =>
  statusItems.value.reduce((sum, i) => sum + i.count, 0)
);

async function fetchReport() {
  isLoading.value = true;
  try {
    const range = getDateRange(selectedPreset.value);
    const params = { since: range.since, until: range.until };
    if (selectedAgent.value) {
      params.userId = selectedAgent.value;
    }
    const response = await AgendaReportsAPI.getSummary(params);
    reportData.value = response.data;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[AgendaReports] Error:', error);
  } finally {
    isLoading.value = false;
  }
}

const forecastData = ref(null);
const forecastHorizon = ref(7);
const forecastLoading = ref(false);

const FORECAST_HORIZONS = [7, 14, 30];

const forecastDays = computed(() => forecastData.value?.forecast || []);
const forecastMaxTotal = computed(() => {
  const vals = forecastDays.value.map(d => d.predicted_total);
  return Math.max(...vals, 1);
});

async function fetchForecast() {
  forecastLoading.value = true;
  try {
    const params = { days: forecastHorizon.value };
    if (selectedAgent.value) params.userId = selectedAgent.value;
    const response = await AgendaReportsAPI.getForecast(params);
    forecastData.value = response.data;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[AgendaReports] Forecast error:', error);
  } finally {
    forecastLoading.value = false;
  }
}

watch([forecastHorizon, selectedAgent], () => fetchForecast());

watch([selectedPreset, selectedAgent], () => fetchReport());

onMounted(() => {
  store.dispatch('agents/get');
  fetchReport();
  fetchForecast();
});

function formatDayLabel(dateStr) {
  const d = new Date(`${dateStr}T12:00:00`);
  const weekday = d.toLocaleDateString('pt-BR', { weekday: 'short' });
  const day = d.getDate();
  const month = d.toLocaleDateString('pt-BR', { month: 'short' });
  return `${weekday}\n${day} ${month}`;
}

function getComparisonClass(card) {
  const comp = getComparison(card.value, card.previousValue);
  if (comp.direction === 'neutral') return 'comp--neutral';
  const isPositive = card.invertComparison
    ? comp.direction === 'down'
    : comp.direction === 'up';
  return isPositive ? 'comp--positive' : 'comp--negative';
}

function getComparisonIcon(card) {
  const comp = getComparison(card.value, card.previousValue);
  if (comp.direction === 'neutral') return 'i-lucide-minus';
  return comp.direction === 'up'
    ? 'i-lucide-trending-up'
    : 'i-lucide-trending-down';
}

function getComparisonText(card) {
  const comp = getComparison(card.value, card.previousValue);
  if (comp.direction === 'neutral') return '0%';
  return `${comp.pct}%`;
}

function getPresetLabel() {
  const preset = DATE_PRESETS.find(p => p.key === selectedPreset.value);
  return preset ? t(preset.i18nKey) : '';
}

function getPreviousPeriodLabel() {
  if (selectedPreset.value === 'today')
    return t('AGENDA_REPORTS.VS_PREVIOUS.TODAY');
  if (selectedPreset.value === 'yesterday')
    return t('AGENDA_REPORTS.VS_PREVIOUS.YESTERDAY');
  const label = getPresetLabel().toLowerCase();
  return t('AGENDA_REPORTS.VS_PREVIOUS.DEFAULT', { label });
}

function getScheduledCount(day) {
  return (
    day.total - day.completed - day.confirmed - day.no_show - day.cancelled
  );
}

function getBarHeight(total) {
  const pct = total / maxDailyTotal.value;
  return `${Math.max(pct * 140, 4)}px`;
}

function getStatusPct(count) {
  if (!statusTotal.value) return '0';
  return ((count / statusTotal.value) * 100).toFixed(0);
}

function getStatusWidth(count) {
  if (!statusTotal.value) return '0%';
  return `${(count / statusTotal.value) * 100}%`;
}
</script>

<template>
  <div>
    <ReportHeader :header-title="$t('AGENDA_REPORTS.HEADER')" />

    <div class="flex flex-col gap-5 pb-10">
      <!-- Filters -->
      <div class="flex items-center justify-between gap-4 flex-wrap">
        <div class="flex gap-1.5 flex-wrap">
          <button
            v-for="preset in DATE_PRESETS"
            :key="preset.key"
            class="px-3.5 py-1.5 rounded-full text-[13px] font-medium border cursor-pointer transition-all duration-150 whitespace-nowrap"
            :class="
              selectedPreset === preset.key
                ? 'bg-woot-600/12 text-woot-500 border-woot-600/25'
                : 'bg-transparent text-n-slate-10 border-n-weak hover:bg-n-alpha-1 hover:text-n-slate-12'
            "
            @click="selectedPreset = preset.key"
          >
            {{ $t(preset.i18nKey) }}
          </button>
        </div>
        <div class="relative flex items-center">
          <span
            class="i-lucide-user w-4 h-4 text-n-slate-10 absolute left-3 pointer-events-none"
          />
          <select
            v-model="selectedAgent"
            class="bg-n-alpha-1 border border-n-weak text-n-slate-12 rounded-lg py-2 pl-9 pr-3 text-[13px] appearance-none cursor-pointer min-w-[200px] focus:outline-none focus:border-woot-600"
          >
            <option :value="null">
              {{ $t('AGENDA_REPORTS.ALL_SPECIALISTS') }}
            </option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
        </div>
      </div>

      <!-- Loading -->
      <div
        v-if="isLoading"
        class="flex items-center justify-center gap-3 py-16"
      >
        <div
          class="w-6 h-6 border-2 border-n-weak border-t-woot-600 rounded-full animate-spin"
        />
        <span class="text-n-slate-10 text-sm">{{
          $t('AGENDA_REPORTS.LOADING')
        }}</span>
      </div>

      <template v-else-if="reportData">
        <!-- KPI Grid -->
        <div
          class="grid grid-cols-4 gap-3.5 max-lg:grid-cols-2 max-sm:grid-cols-1"
        >
          <div
            v-for="card in kpiCards"
            :key="card.key"
            class="bg-n-alpha-1 border border-n-weak rounded-xl p-4 flex flex-col gap-2.5 transition-colors hover:border-n-strong"
          >
            <div class="flex items-center gap-2.5">
              <div
                class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0"
                :class="card.colorClass"
              >
                <i class="w-4 h-4" :class="card.icon" />
              </div>
              <span class="text-[13px] font-medium text-n-slate-10">
                {{ $t(card.i18nKey) }}
              </span>
            </div>
            <div class="flex items-baseline gap-3">
              <span
                class="text-[28px] font-semibold text-n-slate-12 leading-none"
              >
                {{ card.value }}
              </span>
              <div
                class="flex items-center gap-1 text-xs font-semibold rounded-full px-2 py-0.5"
                :class="getComparisonClass(card)"
              >
                <i class="w-3.5 h-3.5" :class="getComparisonIcon(card)" />
                <span>{{ getComparisonText(card) }}</span>
              </div>
            </div>
            <div class="text-[11px] text-n-slate-9">
              {{ getPreviousPeriodLabel() }}: {{ card.previousValue }}
            </div>
          </div>
        </div>

        <!-- Rate Cards -->
        <div class="grid grid-cols-3 gap-3.5 max-md:grid-cols-1">
          <div
            v-for="card in rateCards"
            :key="card.key"
            class="bg-n-alpha-1 border border-n-weak rounded-xl px-5 py-4 flex items-center justify-between gap-4 transition-colors hover:border-n-strong"
          >
            <div class="flex items-center gap-3.5">
              <div
                class="w-[42px] h-[42px] rounded-[10px] flex items-center justify-center flex-shrink-0"
                :class="card.colorClass"
              >
                <i class="w-5 h-5" :class="card.icon" />
              </div>
              <div class="flex flex-col gap-1">
                <span class="text-sm font-medium text-n-slate-11">
                  {{ $t(card.i18nKey) }}
                </span>
                <div
                  class="flex items-center gap-1 text-[11px] font-medium"
                  :class="getComparisonClass(card)"
                >
                  <i class="w-3 h-3" :class="getComparisonIcon(card)" />
                  <span>
                    {{ getComparisonText(card) }}
                    {{ getPreviousPeriodLabel() }}
                  </span>
                </div>
              </div>
            </div>
            <span class="text-[32px] font-bold text-n-slate-12 leading-none">
              {{ card.value }}%
            </span>
          </div>
        </div>

        <!-- Charts -->
        <div class="grid grid-cols-[1.6fr_1fr] gap-3.5 max-md:grid-cols-1">
          <!-- Daily Distribution -->
          <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-5">
            <div class="flex items-baseline justify-between mb-4">
              <h4 class="text-sm font-semibold text-n-slate-12 m-0">
                {{ $t('AGENDA_REPORTS.CHART.DAILY_DISTRIBUTION') }}
              </h4>
              <span class="text-xs text-n-slate-10">{{
                getPresetLabel()
              }}</span>
            </div>
            <div class="flex items-end gap-2 min-h-[180px] pb-2">
              <div
                v-for="day in dailyDistribution"
                :key="day.date"
                class="flex-1 flex flex-col items-center gap-1.5"
              >
                <div
                  class="w-full max-w-[40px] rounded-t-md overflow-hidden flex flex-col"
                  :style="{ height: getBarHeight(day.total) }"
                >
                  <div
                    v-if="day.completed"
                    class="bg-emerald-500 min-h-[2px]"
                    :style="{ flex: day.completed }"
                  />
                  <div
                    v-if="day.confirmed"
                    class="bg-green-500 min-h-[2px]"
                    :style="{ flex: day.confirmed }"
                  />
                  <div
                    v-if="getScheduledCount(day) > 0"
                    class="bg-woot-600 min-h-[2px]"
                    :style="{ flex: getScheduledCount(day) }"
                  />
                  <div
                    v-if="day.no_show"
                    class="bg-red-500 min-h-[2px]"
                    :style="{ flex: day.no_show }"
                  />
                  <div
                    v-if="day.cancelled"
                    class="bg-n-slate-10 min-h-[2px]"
                    :style="{ flex: day.cancelled }"
                  />
                </div>
                <span
                  class="text-[10px] text-n-slate-10 text-center whitespace-pre-line leading-tight"
                >
                  {{ formatDayLabel(day.date) }}
                </span>
                <span class="text-xs font-semibold text-n-slate-11">{{
                  day.total
                }}</span>
              </div>
            </div>
            <div class="flex gap-3.5 mt-3.5 flex-wrap">
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2 h-2 rounded-sm bg-emerald-500" />
                {{ $t('AGENDA_REPORTS.LEGEND.COMPLETED') }}
              </span>
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2 h-2 rounded-sm bg-green-500" />
                {{ $t('AGENDA_REPORTS.LEGEND.CONFIRMED') }}
              </span>
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2 h-2 rounded-sm bg-woot-600" />
                {{ $t('AGENDA_REPORTS.LEGEND.SCHEDULED') }}
              </span>
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2 h-2 rounded-sm bg-red-500" />
                {{ $t('AGENDA_REPORTS.LEGEND.NO_SHOW') }}
              </span>
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2 h-2 rounded-sm bg-n-slate-10" />
                {{ $t('AGENDA_REPORTS.LEGEND.CANCELLED') }}
              </span>
            </div>
          </div>

          <!-- Status Breakdown -->
          <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-5">
            <div class="flex items-baseline justify-between mb-4">
              <h4 class="text-sm font-semibold text-n-slate-12 m-0">
                {{ $t('AGENDA_REPORTS.CHART.STATUS_BREAKDOWN') }}
              </h4>
              <span class="text-xs text-n-slate-10">{{
                getPresetLabel()
              }}</span>
            </div>
            <div v-if="statusTotal > 0" class="flex flex-col gap-4">
              <div class="flex h-3.5 rounded-full overflow-hidden gap-0.5">
                <div
                  v-for="item in statusItems"
                  :key="item.key"
                  class="min-w-1 transition-[width] duration-300"
                  :style="{
                    width: getStatusWidth(item.count),
                    backgroundColor: item.color,
                  }"
                />
              </div>
              <div class="flex flex-col gap-2.5">
                <div
                  v-for="item in statusItems"
                  :key="item.key"
                  class="flex items-center gap-2.5"
                >
                  <span
                    class="w-2.5 h-2.5 rounded flex-shrink-0"
                    :style="{ backgroundColor: item.color }"
                  />
                  <span class="text-[13px] text-n-slate-11 flex-1">{{
                    $t(item.i18nKey)
                  }}</span>
                  <span
                    class="text-sm font-semibold text-n-slate-12 min-w-[32px] text-right"
                  >
                    {{ item.count }}
                  </span>
                  <span class="text-xs text-n-slate-10 min-w-[36px] text-right">
                    {{ getStatusPct(item.count) }}%
                  </span>
                </div>
              </div>
            </div>
            <div
              v-else
              class="flex flex-col items-center justify-center gap-2 py-10 text-n-slate-9"
            >
              <i class="i-lucide-bar-chart-3 w-8 h-8" />
              <span class="text-sm">{{
                $t('AGENDA_REPORTS.EMPTY.NO_EVENTS')
              }}</span>
            </div>
          </div>
        </div>

        <!-- Agent Performance -->
        <div
          v-if="agentPerformance.length"
          class="bg-n-alpha-1 border border-n-weak rounded-xl p-5 overflow-hidden"
        >
          <div class="flex items-baseline justify-between mb-4">
            <h4 class="text-sm font-semibold text-n-slate-12 m-0">
              {{ $t('AGENDA_REPORTS.CHART.AGENT_PERFORMANCE') }}
            </h4>
            <span class="text-xs text-n-slate-10">{{ getPresetLabel() }}</span>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full border-collapse">
              <thead>
                <tr>
                  <th class="ar-th text-left">
                    {{ $t('AGENDA_REPORTS.TABLE.SPECIALIST') }}
                  </th>
                  <th class="ar-th text-center">
                    {{ $t('AGENDA_REPORTS.TABLE.TOTAL') }}
                  </th>
                  <th class="ar-th text-center">
                    {{ $t('AGENDA_REPORTS.TABLE.COMPLETED') }}
                  </th>
                  <th class="ar-th text-center">
                    {{ $t('AGENDA_REPORTS.TABLE.NO_SHOW') }}
                  </th>
                  <th class="ar-th text-center">
                    {{ $t('AGENDA_REPORTS.TABLE.CANCELLED') }}
                  </th>
                  <th class="ar-th text-center">
                    {{ $t('AGENDA_REPORTS.TABLE.EFFICIENCY') }}
                  </th>
                  <th class="ar-th text-center">
                    {{ $t('AGENDA_REPORTS.TABLE.NO_SHOW_RATE') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="agent in agentPerformance"
                  :key="agent.id"
                  class="transition-colors hover:bg-n-alpha-1"
                >
                  <td
                    class="px-3.5 py-3 text-sm text-n-slate-12 border-b border-n-alpha-1 align-middle"
                  >
                    <div class="flex items-center gap-2.5">
                      <div
                        class="w-8 h-8 rounded-lg bg-woot-600/12 text-woot-500 flex items-center justify-center text-sm font-semibold flex-shrink-0"
                      >
                        {{ agent.name.charAt(0).toUpperCase() }}
                      </div>
                      <span class="font-medium">{{ agent.name }}</span>
                    </div>
                  </td>
                  <td
                    class="px-3.5 py-3 text-sm text-n-slate-12 text-center border-b border-n-alpha-1 align-middle"
                  >
                    {{ agent.total }}
                  </td>
                  <td
                    class="px-3.5 py-3 text-center border-b border-n-alpha-1 align-middle"
                  >
                    <span
                      class="inline-flex items-center justify-center px-2.5 py-0.5 rounded-full text-xs font-semibold text-green-400 bg-green-500/10 min-w-[28px]"
                    >
                      {{ agent.completed }}
                    </span>
                  </td>
                  <td
                    class="px-3.5 py-3 text-center border-b border-n-alpha-1 align-middle"
                  >
                    <span
                      class="inline-flex items-center justify-center px-2.5 py-0.5 rounded-full text-xs font-semibold text-red-400 bg-red-500/10 min-w-[28px]"
                    >
                      {{ agent.no_show }}
                    </span>
                  </td>
                  <td
                    class="px-3.5 py-3 text-center border-b border-n-alpha-1 align-middle"
                  >
                    <span
                      class="inline-flex items-center justify-center px-2.5 py-0.5 rounded-full text-xs font-semibold text-n-slate-10 bg-n-alpha-1 min-w-[28px]"
                    >
                      {{ agent.cancelled }}
                    </span>
                  </td>
                  <td
                    class="px-3.5 py-3 text-center border-b border-n-alpha-1 align-middle"
                  >
                    <div class="flex items-center gap-2">
                      <div
                        class="flex-1 h-1.5 bg-n-alpha-1 rounded-full overflow-hidden min-w-[60px]"
                      >
                        <div
                          class="h-full bg-emerald-500 rounded-full transition-[width] duration-300"
                          :style="{ width: `${agent.completion_rate}%` }"
                        />
                      </div>
                      <span
                        class="text-xs font-semibold text-n-slate-10 min-w-[38px] text-right"
                      >
                        {{ agent.completion_rate }}%
                      </span>
                    </div>
                  </td>
                  <td
                    class="px-3.5 py-3 text-center border-b border-n-alpha-1 align-middle"
                  >
                    <div class="flex items-center gap-2">
                      <div
                        class="flex-1 h-1.5 bg-n-alpha-1 rounded-full overflow-hidden min-w-[60px]"
                      >
                        <div
                          class="h-full bg-red-500 rounded-full transition-[width] duration-300"
                          :style="{ width: `${agent.no_show_rate}%` }"
                        />
                      </div>
                      <span
                        class="text-xs font-semibold text-n-slate-10 min-w-[38px] text-right"
                      >
                        {{ agent.no_show_rate }}%
                      </span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Forecast / Previsibilidade -->
        <div class="bg-n-alpha-1 border border-n-weak rounded-xl p-5">
          <div class="flex items-center justify-between mb-4 flex-wrap gap-3">
            <div>
              <h4 class="text-sm font-semibold text-n-slate-12 m-0">
                {{ $t('AGENDA_REPORTS.FORECAST.TITLE') }}
              </h4>
              <p class="text-xs text-n-slate-10 mt-0.5 m-0">
                {{ $t('AGENDA_REPORTS.FORECAST.SUBTITLE') }}
              </p>
            </div>
            <div class="flex gap-1.5">
              <button
                v-for="h in FORECAST_HORIZONS"
                :key="h"
                class="px-3 py-1 rounded-full text-[12px] font-medium border cursor-pointer transition-all"
                :class="
                  forecastHorizon === h
                    ? 'bg-woot-600/12 text-woot-500 border-woot-600/25'
                    : 'bg-transparent text-n-slate-10 border-n-weak hover:bg-n-alpha-1'
                "
                @click="forecastHorizon = h"
              >
                {{ h }} {{ $t('AGENDA_REPORTS.FORECAST.DAYS') }}
              </button>
            </div>
          </div>

          <div
            v-if="forecastLoading"
            class="flex items-center justify-center py-10 gap-2"
          >
            <div
              class="w-5 h-5 border-2 border-n-weak border-t-woot-600 rounded-full animate-spin"
            />
            <span class="text-n-slate-10 text-xs">{{
              $t('AGENDA_REPORTS.LOADING')
            }}</span>
          </div>

          <div v-else-if="forecastDays.length" class="flex flex-col gap-3">
            <div
              v-for="day in forecastDays"
              :key="day.date"
              class="flex items-center gap-3"
            >
              <!-- Day label -->
              <div class="w-24 flex-shrink-0 text-right">
                <div class="text-[11px] font-medium text-n-slate-11 capitalize">
                  {{ day.label }}
                </div>
                <div class="text-[10px] text-n-slate-9">
                  {{
                    new Date(day.date + 'T12:00:00').toLocaleDateString(
                      'pt-BR',
                      { day: '2-digit', month: 'short' }
                    )
                  }}
                </div>
              </div>

              <!-- Bar -->
              <div
                class="flex-1 h-6 bg-n-alpha-2 rounded-md overflow-hidden relative"
              >
                <div
                  class="h-full rounded-md transition-[width] duration-500 flex items-center pr-2"
                  :class="
                    day.predicted_occupancy >= 80
                      ? 'bg-red-500/25'
                      : day.predicted_occupancy >= 50
                        ? 'bg-amber-500/25'
                        : 'bg-woot-600/20'
                  "
                  :style="{
                    width: `${Math.max((day.predicted_total / forecastMaxTotal) * 100, 4)}%`,
                  }"
                />
                <span
                  class="absolute left-2 top-1/2 -translate-y-1/2 text-[11px] font-semibold text-n-slate-11"
                >
                  {{ day.predicted_total }}
                  {{ $t('AGENDA_REPORTS.FORECAST.APPTS') }}
                </span>
              </div>

              <!-- Occupancy badge -->
              <div
                class="w-14 flex-shrink-0 text-center px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                :class="
                  day.predicted_occupancy >= 80
                    ? 'bg-red-500/15 text-red-400'
                    : day.predicted_occupancy >= 50
                      ? 'bg-amber-500/15 text-amber-400'
                      : 'bg-emerald-500/15 text-emerald-400'
                "
              >
                {{ day.predicted_occupancy }}%
              </div>
            </div>

            <!-- Legend -->
            <div class="flex gap-4 mt-1 flex-wrap">
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2.5 h-2.5 rounded-sm bg-emerald-500/40" />
                {{ $t('AGENDA_REPORTS.FORECAST.LOW') }}
              </span>
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2.5 h-2.5 rounded-sm bg-amber-500/40" />
                {{ $t('AGENDA_REPORTS.FORECAST.MEDIUM') }}
              </span>
              <span
                class="flex items-center gap-1.5 text-[11px] text-n-slate-10"
              >
                <span class="w-2.5 h-2.5 rounded-sm bg-red-500/40" />
                {{ $t('AGENDA_REPORTS.FORECAST.HIGH') }}
              </span>
              <span class="text-[11px] text-n-slate-9 ml-auto">
                {{
                  $t('AGENDA_REPORTS.FORECAST.BASED_ON', {
                    days: forecastData?.history_days || 28,
                  })
                }}
              </span>
            </div>
          </div>

          <div
            v-else
            class="flex flex-col items-center justify-center gap-2 py-8 text-n-slate-9"
          >
            <i class="i-lucide-calendar-clock w-8 h-8" />
            <span class="text-sm">{{
              $t('AGENDA_REPORTS.FORECAST.EMPTY')
            }}</span>
          </div>
        </div>
      </template>

      <!-- Empty -->
      <div
        v-else
        class="flex flex-col items-center justify-center gap-2 py-20 text-n-slate-9 text-center"
      >
        <i class="i-lucide-calendar-off w-12 h-12" />
        <h3 class="text-n-slate-11 font-semibold m-0">
          {{ $t('AGENDA_REPORTS.EMPTY.TITLE') }}
        </h3>
        <p class="text-n-slate-10 text-sm m-0">
          {{ $t('AGENDA_REPORTS.EMPTY.DESCRIPTION') }}
        </p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.kpi--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}
.kpi--green {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.kpi--amber {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
}
.kpi--emerald {
  background: rgba(16, 185, 129, 0.1);
  color: #34d399;
}
.kpi--cyan {
  background: rgba(6, 182, 212, 0.1);
  color: #22d3ee;
}
.kpi--purple {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
}
.kpi--red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}
.kpi--slate {
  background: rgba(100, 116, 139, 0.1);
  color: #94a3b8;
}

.rate--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}
.rate--red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}
.rate--emerald {
  background: rgba(16, 185, 129, 0.1);
  color: #34d399;
}

.comp--positive {
  color: #4ade80;
  background: rgba(34, 197, 94, 0.1);
}
.comp--negative {
  color: #f87171;
  background: rgba(239, 68, 68, 0.1);
}
.comp--neutral {
  color: #64748b;
  background: rgba(100, 116, 139, 0.08);
}

.ar-th {
  @apply text-[11px] font-semibold uppercase tracking-wider text-n-slate-10 px-3.5 py-2.5 border-b border-n-weak;
}
</style>
