<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  BarElement,
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
  data: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
});

ChartJS.register(
  BarElement,
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

const isMarginCompressing = computed(() => {
  if (props.data.length < 3) return false;
  const last3 = props.data.slice(-3);
  const marginTrend = last3.map(d => (d.fixo + d.variavel) / (d.receita || 1));
  return marginTrend[2] > marginTrend[0];
});

const chartData = computed(() => ({
  labels: props.data.map(d => d.mes),
  datasets: [
    {
      type: 'bar',
      label: t('FINANCIAL.CHARTS.COST_STRUCTURE.FIXED'),
      data: props.data.map(d => d.fixo),
      backgroundColor: '#FCA5A5',
      stack: 's',
      borderRadius: 2,
      order: 2,
    },
    {
      type: 'bar',
      label: t('FINANCIAL.CHARTS.COST_STRUCTURE.VARIABLE'),
      data: props.data.map(d => d.variavel),
      backgroundColor: '#FED7AA',
      stack: 's',
      borderRadius: 2,
      order: 2,
    },
    {
      type: 'line',
      label: t('FINANCIAL.CHARTS.COST_STRUCTURE.REVENUE'),
      data: props.data.map(d => d.receita),
      borderColor: '#10B981',
      borderWidth: 2,
      pointRadius: 3,
      fill: false,
      tension: 0.3,
      yAxisID: 'y2',
      order: 1,
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
      callbacks: {
        label: ctx => ` ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`,
      },
    },
  },
  scales: {
    x: {
      stacked: true,
      grid: { display: false },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
      },
    },
    y: {
      stacked: true,
      grid: { color: isDark.value ? '#334155' : '#E2E8F0' },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
        callback: v => formatBRL(v),
      },
    },
    y2: {
      position: 'right',
      grid: { drawOnChartArea: false },
      ticks: {
        color: '#10B981',
        font: { size: 11 },
        callback: v => formatBRL(v),
      },
    },
  },
}));
</script>

<template>
  <div class="coststr-wrapper">
    <div v-if="isMarginCompressing" class="coststr-alert">
      <i class="i-lucide-alert-triangle coststr-alert__icon" />
      <span>{{ t('FINANCIAL.CHARTS.COST_STRUCTURE.ALERT_COMPRESSION') }}</span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="250px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="coststr-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
      <div class="coststr-legend">
        <span class="coststr-legend__item coststr-legend__item--fixed">
          {{ t('FINANCIAL.CHARTS.COST_STRUCTURE.FIXED') }}
        </span>
        <span class="coststr-legend__item coststr-legend__item--variable">
          {{ t('FINANCIAL.CHARTS.COST_STRUCTURE.VARIABLE') }}
        </span>
        <span class="coststr-legend__item coststr-legend__item--revenue">
          {{ t('FINANCIAL.CHARTS.COST_STRUCTURE.REVENUE') }}
        </span>
      </div>
    </template>
  </div>
</template>
