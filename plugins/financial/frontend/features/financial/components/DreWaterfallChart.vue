<script setup>
import { ref, computed, watch } from 'vue';
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
  regime: { type: String, default: 'caixa' },
});

const emit = defineEmits(['regimeChange']);

ChartJS.register(BarElement, LinearScale, CategoryScale, Tooltip, Legend);

const { isDark, defaultTooltip, formatBRL } = useChart();
const { t } = useI18n();

const selectedRegime = ref(props.regime);

watch(selectedRegime, val => emit('regimeChange', val));

const isNegative = computed(() => {
  const final = props.data.find(d => d.tipo === 'final');
  return final && final.valor < 0;
});

const barColors = computed(() =>
  props.data.map(d => {
    if (d.tipo === 'reducao') return '#EF4444';
    if (d.tipo === 'subtotal') return '#10B981';
    if (d.tipo === 'final') return d.valor >= 0 ? '#059669' : '#DC2626';
    return '#64748B';
  })
);

// Plugin para conectar barras com linhas tracejadas
const connectorPlugin = {
  id: 'waterfallConnector',
  afterDatasetsDraw(chart) {
    const { ctx, data: chartData } = chart;
    const meta = chart.getDatasetMeta(0);
    if (!meta.data.length) return;
    ctx.save();
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = isDark.value ? '#475569' : '#CBD5E1';
    ctx.lineWidth = 1;
    for (let i = 0; i < meta.data.length - 1; i += 1) {
      const bar = meta.data[i];
      const nextBar = meta.data[i + 1];
      const y = chart.scales.y.getPixelForValue(
        chartData.datasets[0].data[i][1]
      );
      ctx.beginPath();
      ctx.moveTo(bar.x + bar.width / 2, y);
      ctx.lineTo(nextBar.x - nextBar.width / 2, y);
      ctx.stroke();
    }
    ctx.restore();
  },
};

const chartData = computed(() => ({
  labels: props.data.map(d => d.linha),
  datasets: [
    {
      data: props.data.map(d => [d.base, d.topo]),
      backgroundColor: barColors.value,
      borderSkipped: false,
      borderRadius: 3,
      barThickness: 28,
    },
  ],
}));

const chartOptions = computed(() => ({
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
            ` ${formatBRL(row.valor)}`,
            ` ${row.percentual > 0 ? '+' : ''}${row.percentual}% da receita bruta`,
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
        font: { size: 10 },
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
  <div class="dre-wrapper" :class="{ 'dre-wrapper--negative': isNegative }">
    <!-- Regime toggle -->
    <div class="dre-filters">
      <span class="dre-filters__label">{{
        t('FINANCIAL.CHARTS.DRE.REGIME')
      }}</span>
      <div class="dre-regime-btns">
        <button
          v-for="r in ['caixa', 'competencia']"
          :key="r"
          class="dre-regime-btn"
          :class="{ 'dre-regime-btn--active': selectedRegime === r }"
          @click="selectedRegime = r"
        >
          {{ t(`FINANCIAL.CHARTS.DRE.REGIME_${r.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <!-- Alerta resultado negativo -->
    <div v-if="isNegative" class="dre-alert">
      <i class="i-lucide-trending-down dre-alert__icon" />
      <span>{{ t('FINANCIAL.CHARTS.DRE.ALERT_NEGATIVE') }}</span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="280px" />
    </template>
    <template v-else-if="!data.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="dre-canvas-wrapper">
        <Bar
          :data="chartData"
          :options="chartOptions"
          :plugins="[connectorPlugin]"
        />
      </div>
    </template>
  </div>
</template>
