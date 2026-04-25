<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  LineElement,
  PointElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';
import { Bar } from 'vue-chartjs';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: {
    type: Object,
    default: () => ({ monthly: [], alert: false, meta_pct: 65.0 }),
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  LineElement,
  PointElement,
  Title,
  Tooltip,
  Legend
);

const { t } = useI18n();
const { gridColor, tickColor, defaultTooltip } = useChart();

const isEmpty = computed(() => {
  return !props.data || !props.data.monthly || props.data.monthly.length === 0;
});

const chartData = computed(() => {
  if (isEmpty.value) return { labels: [], datasets: [] };

  const { monthly, meta_pct } = props.data;
  const labels = monthly.map(m => m.mes);
  const novos = monthly.map(m => m.novos);
  const recorrentes = monthly.map(m => m.recorrentes);
  const pcts = monthly.map(m => m.pct_recorrentes);
  const metas = monthly.map(() => meta_pct);

  return {
    labels,
    datasets: [
      {
        type: 'line',
        label: '% Retenção',
        data: pcts,
        borderColor: '#7C3AED',
        backgroundColor: '#7C3AED',
        borderWidth: 2,
        yAxisID: 'y2',
        tension: 0.3,
        pointRadius: 4,
        pointBackgroundColor: '#fff',
        order: 1,
      },
      {
        type: 'line',
        label: 'Meta Ref.',
        data: metas,
        borderColor: '#94A3B8',
        borderWidth: 1.5,
        borderDash: [4, 4],
        yAxisID: 'y2',
        pointRadius: 0,
        fill: false,
        order: 2,
      },
      {
        type: 'bar',
        label: 'Recorrentes',
        data: recorrentes,
        backgroundColor: '#1D4ED8',
        stack: 'Stack 0',
        borderRadius: { topLeft: 4, topRight: 4 },
        order: 3,
      },
      {
        type: 'bar',
        label: 'Novos',
        data: novos,
        backgroundColor: '#BFDBFE',
        stack: 'Stack 0',
        order: 4,
      },
    ],
  };
});

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: {
    mode: 'index',
    intersect: false,
  },
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: context => {
          let label = context.dataset.label || '';
          if (label) label += ': ';
          if (context.dataset.yAxisID === 'y2') {
            label += context.parsed.y + '%';
          } else {
            label += context.parsed.y;
          }
          return label;
        },
      },
    },
  },
  scales: {
    x: {
      stacked: true,
      grid: { display: false },
      ticks: { color: tickColor(), font: { size: 11 } },
    },
    y: {
      stacked: true,
      position: 'left',
      grid: { color: gridColor(), drawBorder: false },
      border: { display: false },
      ticks: {
        color: tickColor(),
        font: { size: 11 },
        padding: 8,
      },
    },
    y2: {
      position: 'right',
      grid: { display: false },
      border: { display: false },
      min: 0,
      max: 100,
      ticks: {
        color: tickColor(),
        font: { size: 11 },
        callback: val => val + '%',
        padding: 8,
      },
    },
  },
}));
</script>

<template>
  <div class="retention-wrapper">
    <template v-if="loading">
      <ChartSkeleton height="260px" />
    </template>
    <template v-else-if="isEmpty">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div v-if="data.alert" class="retention-alert">
        <i class="i-lucide-alert-circle" />
        {{ t('FINANCIAL.CHARTS.RETENTION.ALERT_CHURN') }}
      </div>
      <div class="retention-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
      <div class="retention-legend">
        <div class="retention-legend__item retention-legend__item--new">
          {{ t('FINANCIAL.CHARTS.RETENTION.NEW') }}
        </div>
        <div class="retention-legend__item retention-legend__item--returning">
          {{ t('FINANCIAL.CHARTS.RETENTION.RETURNING') }}
        </div>
        <div class="retention-legend__item retention-legend__item--pct">
          {{ t('FINANCIAL.CHARTS.RETENTION.PCT') }}
        </div>
      </div>
    </template>
  </div>
</template>
