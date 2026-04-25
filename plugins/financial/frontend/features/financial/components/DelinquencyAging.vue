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
  threshold: { type: Number, default: 0 },
});

const emit = defineEmits(['bandClick']);

ChartJS.register(BarElement, LinearScale, CategoryScale, Tooltip);

const { isDark, defaultTooltip, formatBRL } = useChart();
const { t } = useI18n();

const BAND_COLORS = ['#FCD34D', '#F97316', '#EF4444', '#991B1B'];

const total = computed(() => props.data.reduce((s, d) => s + d.valor, 0));

const overThreshold = computed(
  () => props.threshold > 0 && total.value > props.threshold
);

const chartData = computed(() => ({
  labels: props.data.map(d => d.faixa),
  datasets: [
    {
      data: props.data.map(d => d.valor),
      backgroundColor: BAND_COLORS.slice(0, props.data.length),
      borderRadius: 4,
      barThickness: 28,
    },
  ],
}));

const chartOptions = computed(() => ({
  indexAxis: 'y',
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx => {
          const row = props.data[ctx.dataIndex];
          return [
            ` ${formatBRL(ctx.raw)}`,
            ` ${row.pacientes} pacientes · ${row.percentual}%`,
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
  onClick: (_e, elements) => {
    if (elements.length) emit('bandClick', props.data[elements[0].index]);
  },
}));
</script>

<template>
  <div
    class="aging-wrapper"
    :class="{ 'aging-wrapper--danger': overThreshold }"
  >
    <!-- Total no topo -->
    <div class="aging-header">
      <span class="aging-header__label">
        {{ t('FINANCIAL.CHARTS.AGING.TOTAL') }}
        <strong>{{ formatBRL(total) }}</strong>
      </span>
      <span v-if="overThreshold" class="aging-alert-badge">
        {{ t('FINANCIAL.CHARTS.AGING.ALERT_THRESHOLD') }}
      </span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="190px" :bars="4" />
    </template>
    <template v-else-if="!data.length || total === 0">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.AGING.EMPTY_POSITIVE')" />
    </template>
    <template v-else>
      <div class="aging-canvas-wrapper">
        <Bar :data="chartData" :options="chartOptions" />
      </div>
    </template>
  </div>
</template>
