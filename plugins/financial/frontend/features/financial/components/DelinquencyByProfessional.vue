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
} from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
});

ChartJS.register(BarElement, LinearScale, CategoryScale, Tooltip);

const { isDark, defaultTooltip, formatBRL, formatPct } = useChart();
const { t } = useI18n();

function barColor(pct) {
  if (pct < 5) return '#10B981';
  if (pct < 15) return '#F59E0B';
  return '#EF4444';
}

// Plugin que desenha o percentual à direita de cada barra
const pctLabelPlugin = {
  id: 'pctLabel',
  afterDraw(chart) {
    const { ctx, data } = chart;
    const ds = data.datasets[0];
    if (!ds) return;
    const meta = chart.getDatasetMeta(0);
    meta.data.forEach((bar, i) => {
      const row = props.data[i];
      if (!row) return;
      const x = bar.x + bar.width / 2 + 6;
      const y = bar.y + bar.height / 2 + 4;
      ctx.save();
      ctx.font = '11px Inter, sans-serif';
      ctx.fillStyle = barColor(row.percentual);
      ctx.fillText(`${row.percentual}%`, x, y);
      ctx.restore();
    });
  },
};

const chartData = computed(() => ({
  labels: props.data.map(d => d.nome),
  datasets: [
    {
      data: props.data.map(d => d.inadimplente),
      backgroundColor: props.data.map(d => barColor(d.percentual)),
      borderRadius: 4,
      barThickness: 22,
    },
  ],
}));

const chartOptions = computed(() => ({
  indexAxis: 'y',
  responsive: true,
  maintainAspectRatio: false,
  layout: { padding: { right: 48 } },
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx => {
          const row = props.data[ctx.dataIndex];
          return [
            ` ${t('FINANCIAL.CHARTS.DELINQUENCY_PROF.DELINQUENT')}: ${formatBRL(ctx.raw)}`,
            ` ${t('FINANCIAL.CHARTS.DELINQUENCY_PROF.PRODUCTION')}: ${formatBRL(row.producao)}`,
            ` ${t('FINANCIAL.CHARTS.DELINQUENCY_PROF.PCT')}: ${formatPct(row.percentual)}`,
          ];
        },
      },
    },
  },
  scales: {
    x: {
      grid: { color: isDark.value ? '#334155' : '#E2E8F0' },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 11 },
        callback: v => formatBRL(v),
      },
    },
    y: {
      grid: { display: false },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 12 },
      },
    },
  },
}));

// Registrar plugin uma vez
ChartJS.register(pctLabelPlugin);
</script>

<template>
  <div class="dprof-wrapper">
    <template v-if="loading">
      <ChartSkeleton height="220px" :bars="5" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="dprof-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
      <div class="dprof-legend">
        <span class="dprof-legend__item dprof-legend__item--ok">
          {{ t('FINANCIAL.CHARTS.DELINQUENCY_PROF.OK') }}
        </span>
        <span class="dprof-legend__item dprof-legend__item--medium">
          {{ t('FINANCIAL.CHARTS.DELINQUENCY_PROF.MEDIUM') }}
        </span>
        <span class="dprof-legend__item dprof-legend__item--high">
          {{ t('FINANCIAL.CHARTS.DELINQUENCY_PROF.HIGH') }}
        </span>
      </div>
    </template>
  </div>
</template>
