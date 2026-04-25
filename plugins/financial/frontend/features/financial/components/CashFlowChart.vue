<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['alert']);

ChartJS.register(
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Legend,
  Filler
);

const { isDark, defaultTooltip, formatBRL, formatShort } = useChart();
const { t } = useI18n();
const chartRef = ref(null);

const hasNegativeBalance = computed(() =>
  props.data.some(d => d.saldo_acumulado < 0)
);

const totalBalance = computed(() => {
  if (!props.data.length) return 0;
  return props.data.reduce((acc, d) => acc + (d.entradas - d.saidas), 0);
});

const balanceIsPositive = computed(() => totalBalance.value >= 0);

// Plugin crosshair vertical ao hover
const crosshairPlugin = {
  id: 'crosshair',
  afterDraw(chart) {
    const active = chart.tooltip.getActiveElements();
    if (!active || !active.length) return;
    const ctx = chart.ctx;
    const x = active[0].element.x;
    const topY = chart.scales.y.top;
    const bottomY = chart.scales.y.bottom;
    ctx.save();
    ctx.beginPath();
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = isDark.value
      ? 'rgba(148,163,184,0.3)'
      : 'rgba(100,116,139,0.25)';
    ctx.lineWidth = 1;
    ctx.moveTo(x, topY);
    ctx.lineTo(x, bottomY);
    ctx.stroke();
    ctx.restore();
  },
};

function makeGradient(ctx, chartArea, rgbTop, rgbBottom) {
  const gradient = ctx.createLinearGradient(
    0,
    chartArea.top,
    0,
    chartArea.bottom
  );
  gradient.addColorStop(0, rgbTop);
  gradient.addColorStop(1, rgbBottom);
  return gradient;
}

const chartData = computed(() => ({
  labels: props.data.map(d => d.label),
  datasets: [
    {
      label: t('FINANCIAL.CHARTS.CASH_FLOW.ENTRIES'),
      data: props.data.map(d => d.entradas),
      borderColor: '#16a34a',
      backgroundColor(context) {
        const chart = context.chart;
        const { ctx, chartArea } = chart;
        if (!chartArea) return 'transparent';
        return makeGradient(
          ctx,
          chartArea,
          isDark.value ? 'rgba(22,163,74,0.18)' : 'rgba(22,163,74,0.10)',
          'rgba(22,163,74,0)'
        );
      },
      borderWidth: 2.5,
      tension: 0.4,
      fill: true,
      pointRadius: 3,
      pointHoverRadius: 6,
      pointBackgroundColor: '#16a34a',
      pointBorderColor: isDark.value ? '#1e2d25' : '#ffffff',
      pointBorderWidth: 2,
      pointHoverBackgroundColor: '#16a34a',
      pointHoverBorderColor: isDark.value ? '#1e2d25' : '#ffffff',
      pointHoverBorderWidth: 2,
      order: 1,
    },
    {
      label: t('FINANCIAL.CHARTS.CASH_FLOW.EXITS'),
      data: props.data.map(d => d.saidas),
      borderColor: '#dc2626',
      backgroundColor(context) {
        const chart = context.chart;
        const { ctx, chartArea } = chart;
        if (!chartArea) return 'transparent';
        return makeGradient(
          ctx,
          chartArea,
          isDark.value ? 'rgba(220,38,38,0.15)' : 'rgba(220,38,38,0.08)',
          'rgba(220,38,38,0)'
        );
      },
      borderWidth: 2.5,
      tension: 0.4,
      fill: true,
      pointRadius: 3,
      pointHoverRadius: 6,
      pointBackgroundColor: '#dc2626',
      pointBorderColor: isDark.value ? '#2d1e1e' : '#ffffff',
      pointBorderWidth: 2,
      pointHoverBackgroundColor: '#dc2626',
      pointHoverBorderColor: isDark.value ? '#2d1e1e' : '#ffffff',
      pointHoverBorderWidth: 2,
      order: 2,
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
      backgroundColor: isDark.value ? '#1e293b' : '#ffffff',
      titleColor: isDark.value ? '#f8fafc' : '#0f172a',
      bodyColor: isDark.value ? '#cbd5e1' : '#475569',
      borderColor: isDark.value ? '#334155' : '#e2e8f0',
      borderWidth: 1,
      borderRadius: 10,
      padding: 12,
      callbacks: {
        title(items) {
          return items[0]?.label ?? '';
        },
        label(ctx) {
          const icon = ctx.datasetIndex === 0 ? '▲' : '▼';
          return ` ${icon} ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`;
        },
        afterBody(items) {
          if (items.length < 2) return [];
          const entradas = items[0]?.raw ?? 0;
          const saidas = items[1]?.raw ?? 0;
          const saldo = entradas - saidas;
          const prefix = saldo >= 0 ? '+' : '';
          return [``, ` Saldo: ${prefix}${formatBRL(saldo)}`];
        },
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      border: { display: false },
      ticks: {
        color: isDark.value ? '#94a3b8' : '#64748b',
        font: { size: 11 },
        maxRotation: 0,
        autoSkip: true,
        maxTicksLimit: 12,
      },
    },
    y: {
      position: 'left',
      grid: {
        color: isDark.value ? '#1e293b' : '#f1f5f9',
        drawBorder: false,
      },
      border: { display: false, dash: [4, 4] },
      ticks: {
        color: isDark.value ? '#94a3b8' : '#64748b',
        font: { size: 11 },
        callback: v => formatShort(v),
        maxTicksLimit: 6,
      },
    },
  },
  animation: {
    duration: 600,
    easing: 'easeInOutQuart',
  },
}));

watch(
  hasNegativeBalance,
  val => {
    if (val) emit('alert', t('FINANCIAL.CHARTS.CASH_FLOW.ALERT_NEGATIVE'));
  },
  { immediate: true }
);

onMounted(() => ChartJS.register(crosshairPlugin));
</script>

<template>
  <div class="ccf-chart-wrapper">
    <!-- Status pill do período -->
    <div v-if="!loading && data.length" class="ccf-chart-header">
      <div
        class="ccf-status-pill"
        :class="
          balanceIsPositive
            ? 'ccf-status-pill--positive'
            : 'ccf-status-pill--negative'
        "
      >
        <i
          :class="
            balanceIsPositive
              ? 'i-lucide-trending-up'
              : 'i-lucide-trending-down'
          "
          class="ccf-status-icon"
        />
        <span>{{
          balanceIsPositive
            ? $t('FINANCIAL.CHARTS.CASH_FLOW.BALANCE_POSITIVE')
            : $t('FINANCIAL.CHARTS.CASH_FLOW.BALANCE_NEGATIVE')
        }}</span>
      </div>
    </div>

    <!-- Alerta saldo negativo acumulado -->
    <div v-if="hasNegativeBalance && !loading" class="ccf-alert">
      <i class="i-lucide-alert-triangle ccf-alert__icon" />
      <span>{{ $t('FINANCIAL.CHARTS.CASH_FLOW.ALERT_NEGATIVE') }}</span>
    </div>

    <!-- Loading skeleton -->
    <template v-if="loading">
      <ChartSkeleton height="280px" />
    </template>

    <!-- Vazio -->
    <template v-else-if="!data.length">
      <ChartEmptyState :message="$t('FINANCIAL.CHARTS.EMPTY')" />
    </template>

    <!-- Gráfico de linhas -->
    <template v-else>
      <div class="ccf-canvas-wrapper">
        <Line ref="chartRef" :data="chartData" :options="chartOptions" />
      </div>

      <!-- Legenda customizada -->
      <div class="ccf-legend">
        <span class="ccf-legend__item">
          <span class="ccf-legend__dot ccf-legend__dot--income" />
          <span class="ccf-legend__line ccf-legend__line--income" />
          {{ $t('FINANCIAL.CHARTS.CASH_FLOW.ENTRIES') }}
        </span>
        <span class="ccf-legend__item">
          <span class="ccf-legend__dot ccf-legend__dot--expense" />
          <span class="ccf-legend__line ccf-legend__line--expense" />
          {{ $t('FINANCIAL.CHARTS.CASH_FLOW.EXITS') }}
        </span>
        <span class="ccf-legend__hint">
          <i class="i-lucide-info ccf-hint-icon" />
          {{ $t('FINANCIAL.CHARTS.CASH_FLOW.LEGEND_HINT') }}
        </span>
      </div>
    </template>
  </div>
</template>
