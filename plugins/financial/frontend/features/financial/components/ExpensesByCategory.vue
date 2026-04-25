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

const emit = defineEmits(['categoryClick']);

ChartJS.register(BarElement, LinearScale, CategoryScale, Tooltip);

const { isDark, defaultTooltip, formatBRL } = useChart();
const { t } = useI18n();

// Escala de âmbar proporcional ao valor
function amberScale(values) {
  const max = Math.max(...values);
  return values.map(v => {
    if (max === 0) return '#FDE68A';
    const ratio = v / max;
    // Interpolação #FDE68A (253,230,138) → #92400E (146,64,14)
    const rV = Math.round(253 + ratio * (146 - 253));
    const gV = Math.round(230 + ratio * (64 - 230));
    const bV = Math.round(138 + ratio * (14 - 138));
    return `rgb(${rV},${gV},${bV})`;
  });
}

const spikeCategories = computed(() =>
  props.data.filter(d => d.variacao_pct > 20).map(d => d.categoria)
);

// Plugin: variação % ao lado de cada barra
const variationPlugin = {
  id: 'expenseVariation',
  afterDatasetsDraw(chart) {
    const { ctx } = chart;
    const meta = chart.getDatasetMeta(0);
    ctx.save();
    ctx.font = '11px sans-serif';
    ctx.textBaseline = 'middle';
    meta.data.forEach((bar, i) => {
      const row = props.data[i];
      if (row == null) return;
      const pct = row.variacao_pct;
      ctx.fillStyle = pct > 0 ? '#EF4444' : '#10B981';
      const label = `${pct > 0 ? '↑' : '↓'} ${Math.abs(pct)}%`;
      ctx.fillText(label, bar.x + bar.width / 2 + 6, bar.y);
    });
    ctx.restore();
  },
};

const chartData = computed(() => ({
  labels: props.data.map(d => d.categoria),
  datasets: [
    {
      data: props.data.map(d => d.total),
      backgroundColor: amberScale(props.data.map(d => d.total)),
      borderRadius: 4,
      barThickness: 22,
    },
  ],
}));

const chartOptions = computed(() => ({
  indexAxis: 'y',
  responsive: true,
  maintainAspectRatio: false,
  layout: { padding: { right: 60 } },
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx => {
          const row = props.data[ctx.dataIndex];
          const sign = row.variacao_pct > 0 ? '+' : '';
          return [
            ` ${formatBRL(ctx.raw)}`,
            ` vs mês anterior: ${sign}${row.variacao_pct}%`,
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
        font: { size: 11 },
      },
    },
  },
  onClick: (_e, elements) => {
    if (elements.length) emit('categoryClick', props.data[elements[0].index]);
  },
}));
</script>

<template>
  <div class="expcategory-wrapper">
    <div v-if="spikeCategories.length" class="expcategory-alert">
      <i class="i-lucide-alert-triangle expcategory-alert__icon" />
      <span>{{
        t('FINANCIAL.CHARTS.EXPENSES_CATEGORY.ALERT_SPIKE', {
          categories: spikeCategories.join(', '),
        })
      }}</span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="260px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="expcategory-canvas-wrapper">
        <Bar
          :data="chartData"
          :options="chartOptions"
          :plugins="[variationPlugin]"
        />
      </div>
    </template>
  </div>
</template>
