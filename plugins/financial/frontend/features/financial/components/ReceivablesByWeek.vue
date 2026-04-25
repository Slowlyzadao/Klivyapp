<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  BarElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Legend,
} from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
});

ChartJS.register(BarElement, LinearScale, CategoryScale, Tooltip, Legend);

const { isDark, defaultTooltip, formatBRL } = useChart();
const { t } = useI18n();

const COLORS = {
  pix: '#10B981',
  dinheiro: '#34D399',
  cartao_debito: '#3B82F6',
  cartao_credito: '#8B5CF6',
  boleto: '#F59E0B',
  convenio: '#6B7280',
  outro: '#94A3B8',
};

const labels = computed(() => props.data.map(d => d.semana));

const datasets = computed(() =>
  Object.keys(COLORS).map(key => ({
    label: t(`FINANCIAL.CHARTS.RECEIVABLES.METHODS.${key.toUpperCase()}`),
    data: props.data.map(d => d[key] ?? 0),
    backgroundColor: COLORS[key],
    borderRadius: 3,
  }))
);

const chartData = computed(() => ({
  labels: labels.value,
  datasets: datasets.value,
}));

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx => ` ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`,
        footer: items => {
          const total = items.reduce((s, i) => s + i.raw, 0);
          return `Total: ${formatBRL(total)}`;
        },
      },
    },
  },
  scales: {
    x: {
      stacked: false,
      grid: { display: false },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
      },
    },
    y: {
      stacked: false,
      grid: { color: isDark.value ? '#334155' : '#E2E8F0' },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
        callback: v => formatBRL(v),
      },
    },
  },
}));
</script>

<template>
  <div class="recv-wrapper">
    <template v-if="loading">
      <ChartSkeleton height="220px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="recv-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
      <!-- Legend customizada -->
      <div class="recv-legend">
        <span
          v-for="(color, key) in COLORS"
          :key="key"
          class="recv-legend__item"
          :style="{ '--c': color }"
        >
          {{ t(`FINANCIAL.CHARTS.RECEIVABLES.METHODS.${key.toUpperCase()}`) }}
        </span>
      </div>
    </template>
  </div>
</template>
