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
  Tooltip,
  Filler,
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
  Tooltip,
  Filler
);

const { isDark, defaultTooltip, formatBRL, formatPct } = useChart();
const { t } = useI18n();

const avg12 = computed(() => {
  if (!props.data.length) return 0;
  return props.data.reduce((s, d) => s + d.percentual, 0) / props.data.length;
});

const isAboveAvg = computed(() => {
  if (!props.data.length) return false;
  const last = props.data.at(-1);
  return last && last.percentual > avg12.value * 1.3;
});

const chartData = computed(() => ({
  labels: props.data.map(d => d.mes),
  datasets: [
    {
      type: 'bar',
      label: t('FINANCIAL.CHARTS.DELINQUENCY_TREND.VALUE'),
      data: props.data.map(d => d.valor_inadimplente),
      backgroundColor: '#FCA5A5',
      borderRadius: 3,
      yAxisID: 'y',
      order: 2,
    },
    {
      type: 'line',
      label: t('FINANCIAL.CHARTS.DELINQUENCY_TREND.PCT'),
      data: props.data.map(d => d.percentual),
      borderColor: '#DC2626',
      backgroundColor: 'transparent',
      borderWidth: 2,
      tension: 0.3,
      pointRadius: 2,
      yAxisID: 'y2',
      order: 1,
    },
    // Linha referência 5%
    {
      type: 'line',
      label: '',
      data: props.data.map(() => 5),
      borderColor: '#94A3B8',
      borderDash: [4, 4],
      borderWidth: 1,
      pointRadius: 0,
      yAxisID: 'y2',
      fill: false,
      order: 3,
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
        label: ctx => {
          if (ctx.dataset.yAxisID === 'y2')
            return ` ${ctx.dataset.label}: ${formatPct(ctx.raw)}`;
          return ` ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`;
        },
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
      },
    },
    y: {
      position: 'left',
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
      min: 0,
      max: 30,
      ticks: {
        color: '#DC2626',
        font: { size: 11 },
        callback: v => `${v}%`,
      },
    },
  },
}));
</script>

<template>
  <div class="dtrend-wrapper">
    <div v-if="isAboveAvg" class="dtrend-alert">
      <i class="i-lucide-trending-up dtrend-alert__icon" />
      <span>{{ t('FINANCIAL.CHARTS.DELINQUENCY_TREND.ALERT_HIGH') }}</span>
    </div>
    <template v-if="loading">
      <ChartSkeleton height="230px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="dtrend-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
      <div class="dtrend-legend">
        <span class="dtrend-legend__item dtrend-legend__item--bar">
          {{ t('FINANCIAL.CHARTS.DELINQUENCY_TREND.VALUE') }}
        </span>
        <span class="dtrend-legend__item dtrend-legend__item--line">
          {{ t('FINANCIAL.CHARTS.DELINQUENCY_TREND.PCT') }}
        </span>
        <span class="dtrend-legend__item dtrend-legend__item--ref">
          {{ t('FINANCIAL.CHARTS.DELINQUENCY_TREND.REF_5PCT') }}
        </span>
      </div>
    </template>
  </div>
</template>
