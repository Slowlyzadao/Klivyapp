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

const hasCommissions = computed(() => props.data.some(d => d.custo_total > 0));

const chartData = computed(() => ({
  labels: props.data.map(d => d.nome),
  datasets: [
    {
      label: t('FINANCIAL.CHARTS.PROF_REVENUE.PRODUCAO'),
      data: props.data.map(d => d.producao),
      backgroundColor: '#BFDBFE',
      borderRadius: 3,
      barThickness: 16,
    },
    {
      label: t('FINANCIAL.CHARTS.PROF_REVENUE.RECEBIDO'),
      data: props.data.map(d => d.recebido),
      backgroundColor: '#3B82F6',
      borderRadius: 3,
      barThickness: 16,
    },
    {
      label: t('FINANCIAL.CHARTS.PROF_REVENUE.CUSTO'),
      data: props.data.map(d => d.custo_total),
      backgroundColor: 'rgba(239,68,68,0.35)',
      borderRadius: 3,
      barThickness: 16,
    },
  ],
}));

const chartOptions = computed(() => ({
  indexAxis: 'y',
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx => ` ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`,
        afterBody: items => {
          const row = props.data[items[0].dataIndex];
          return [`Margem: ${formatBRL(row.margem)} (${row.margem_pct}%)`];
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
</script>

<template>
  <div class="profrev-wrapper">
    <div v-if="!hasCommissions" class="profrev-disclaimer">
      <i class="i-lucide-info profrev-disclaimer__icon" />
      <span>{{
        t('FINANCIAL.CHARTS.PROF_REVENUE.NO_COMMISSION_WARNING')
      }}</span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="240px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="profrev-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
      <div class="profrev-legend">
        <span
          v-for="ds in chartData.datasets"
          :key="ds.label"
          class="profrev-legend__item"
          :style="{ '--c': ds.backgroundColor }"
          >{{ ds.label }}</span>
      </div>
    </template>
  </div>
</template>
