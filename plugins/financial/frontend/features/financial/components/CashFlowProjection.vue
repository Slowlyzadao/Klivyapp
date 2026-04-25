<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Filler,
  Tooltip,
  Legend,
} from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: { type: Object, default: () => ({ atual: 0, projecao: [] }) },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['horizonChange']);

ChartJS.register(
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Filler,
  Tooltip,
  Legend
);

const { isDark, defaultTooltip, formatBRL } = useChart();
const { t } = useI18n();

const horizon = ref(30);

const projection = computed(() => props.data.projecao ?? []);

// Detectar se linha central cruza zero
const negativeDay = computed(() => projection.value.find(d => d.central < 0));

// Dataset faixa de incerteza (área entre otimista e pessimista)
const chartData = computed(() => ({
  labels: projection.value.map(d => d.date.slice(5)), // MM-DD
  datasets: [
    // Área superior (otimista)
    {
      label: t('FINANCIAL.CHARTS.PROJECTION.OPTIMISTIC'),
      data: projection.value.map(d => d.otimista),
      borderColor: 'transparent',
      backgroundColor: 'rgba(59,130,246,0.12)',
      fill: '+1',
      pointRadius: 0,
      tension: 0.3,
    },
    // Linha central
    {
      label: t('FINANCIAL.CHARTS.PROJECTION.CENTRAL'),
      data: projection.value.map(d => d.central),
      borderColor: '#3B82F6',
      backgroundColor: 'transparent',
      borderWidth: 2,
      tension: 0.3,
      pointRadius: 0,
      fill: false,
    },
    // Linha pessimista
    {
      label: t('FINANCIAL.CHARTS.PROJECTION.PESSIMISTIC'),
      data: projection.value.map(d => d.pessimista),
      borderColor: 'transparent',
      backgroundColor: 'rgba(59,130,246,0.12)',
      fill: false,
      pointRadius: 0,
      tension: 0.3,
    },
    // Linha zero tracejada
    {
      label: '',
      data: projection.value.map(() => 0),
      borderColor: '#EF4444',
      borderWidth: 1,
      borderDash: [4, 4],
      pointRadius: 0,
      fill: false,
    },
  ],
}));

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      filter: item => item.dataset.label !== '',
      callbacks: {
        label: ctx => ` ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`,
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
        autoSkip: true,
        maxTicksLimit: 10,
      },
    },
    y: {
      grid: { color: isDark.value ? '#334155' : '#E2E8F0' },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
        callback: v => formatBRL(v),
      },
    },
  },
}));

watch(
  () => horizon.value,
  val => emit('horizonChange', val)
);

onMounted(() => emit('horizonChange', horizon.value));
</script>

<template>
  <div class="proj-wrapper">
    <!-- Filtros + Saldo atual -->
    <div class="proj-header">
      <div class="proj-filters">
        <span class="proj-filters__label">
          {{ t('FINANCIAL.CHARTS.PROJECTION.HORIZON') }}
        </span>
        <div class="proj-horizon-btns">
          <button
            v-for="h in [30, 60, 90]"
            :key="h"
            class="proj-horizon-btn"
            :class="{ 'proj-horizon-btn--active': horizon === h }"
            @click="horizon = h"
          >
            {{ `${h}d` }}
          </button>
        </div>
      </div>

      <!-- Saldo atual badge -->
      <div v-if="!loading && data.atual !== undefined" class="proj-balance-badge" :class="data.atual >= 0 ? 'proj-balance-badge--positive' : 'proj-balance-badge--negative'">
        <i class="i-lucide-landmark proj-balance-badge__icon" />
        <span class="proj-balance-badge__label">{{ t('FINANCIAL.CHARTS.PROJECTION.CURRENT_BALANCE') }}</span>
        <strong class="proj-balance-badge__value">{{ formatBRL(data.atual) }}</strong>
      </div>
    </div>

    <!-- Alerta saldo negativo -->
    <div v-if="negativeDay" class="proj-alert">
      <i class="i-lucide-alert-triangle proj-alert__icon" />
      <span>
        {{
          t('FINANCIAL.CHARTS.PROJECTION.ALERT_NEGATIVE', {
            date: negativeDay.date,
          })
        }}
      </span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="240px" />
    </template>
    <template v-else-if="!projection.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="proj-canvas-wrapper">
        <Line :data="chartData" :options="chartOptions" />
      </div>
      <div class="proj-legend">
        <span class="proj-legend__item proj-legend__item--central">
          {{ t('FINANCIAL.CHARTS.PROJECTION.CENTRAL') }}
        </span>
        <span class="proj-legend__item proj-legend__item--band">
          {{ t('FINANCIAL.CHARTS.PROJECTION.UNCERTAINTY_BAND') }}
        </span>
      </div>
    </template>
  </div>
</template>
