<script setup>
import { computed } from 'vue';
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
  data: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
});

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

// Regressão linear por mínimos quadrados
function linearRegression(values) {
  const n = values.length;
  if (n < 2) return values.map(() => 0);
  const sumX = values.reduce((s, _, i) => s + i, 0);
  const sumY = values.reduce((s, v) => s + v, 0);
  const sumXY = values.reduce((s, v, i) => s + i * v, 0);
  const sumX2 = values.reduce((s, _, i) => s + i * i, 0);
  const denom = n * sumX2 - sumX * sumX;
  if (denom === 0) return values.map(() => sumY / n);
  const slope = (n * sumXY - sumX * sumY) / denom;
  const intercept = (sumY - slope * sumX) / n;
  return values.map((_, i) => Math.round((slope * i + intercept) * 100) / 100);
}

const slope = computed(() => {
  const tickets = props.data.map(d => d.ticket_medio);
  if (tickets.length < 4) return 0;
  const last3 = tickets.slice(-3);
  const n = last3.length;
  const sumX = last3.reduce((s, _, i) => s + i, 0);
  const sumY = last3.reduce((s, v) => s + v, 0);
  const sumXY = last3.reduce((s, v, i) => s + i * v, 0);
  const sumX2 = last3.reduce((s, _, i) => s + i * i, 0);
  const denom = n * sumX2 - sumX * sumX;
  return denom === 0 ? 0 : (n * sumXY - sumX * sumY) / denom;
});

const isTrendDown = computed(() => slope.value < 0);

const tickets = computed(() => props.data.map(d => d.ticket_medio));

const chartData = computed(() => ({
  labels: props.data.map(d => d.mes),
  datasets: [
    {
      label: t('FINANCIAL.CHARTS.TICKET.AVERAGE'),
      data: tickets.value,
      borderColor: '#3B82F6',
      backgroundColor: 'rgba(59,130,246,0.1)',
      tension: 0.3,
      fill: true,
      pointHoverRadius: 6,
      pointBackgroundColor: ctx => {
        const last = props.data.length - 1;
        return ctx.dataIndex === last ? '#1E40AF' : '#3B82F6';
      },
      pointRadius: ctx => (ctx.dataIndex === props.data.length - 1 ? 6 : 3),
    },
    {
      label: t('FINANCIAL.CHARTS.TICKET.TREND'),
      data: linearRegression(tickets.value),
      borderColor: '#94A3B8',
      borderDash: [5, 5],
      pointRadius: 0,
      fill: false,
      tension: 0,
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
        label: ctx => {
          if (ctx.datasetIndex === 1)
            return ` ${t('FINANCIAL.CHARTS.TICKET.TREND')}: ${formatBRL(ctx.raw)}`;
          const row = props.data[ctx.dataIndex];
          return [
            ` ${t('FINANCIAL.CHARTS.TICKET.AVERAGE')}: ${formatBRL(ctx.raw)}`,
            ` ${row.atendimentos} atendimentos`,
          ];
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
  <div class="ticket-wrapper">
    <div v-if="isTrendDown" class="ticket-alert">
      <i class="i-lucide-trending-down ticket-alert__icon" />
      <span>{{ t('FINANCIAL.CHARTS.TICKET.ALERT_DOWN') }}</span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="230px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="ticket-canvas-wrapper">
        <Line :data="chartData" :options="chartOptions" />
      </div>
      <div class="ticket-legend">
        <span class="ticket-legend__item ticket-legend__item--main">
          {{ t('FINANCIAL.CHARTS.TICKET.AVERAGE') }}
        </span>
        <span class="ticket-legend__item ticket-legend__item--trend">
          {{ t('FINANCIAL.CHARTS.TICKET.TREND') }}
        </span>
      </div>
    </template>
  </div>
</template>
