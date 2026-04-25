<script setup>
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Filler,
  Tooltip,
} from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';

const props = defineProps({
  data: {
    type: Object,
    default: () => ({
      entradas_hoje: 0,
      entradas_variacao: 0,
      saidas_hoje: 0,
      saidas_variacao: 0,
      saldo_dia: 0,
      inadimplencia_total: 0,
      sparklines: { entradas: [], saidas: [], saldo: [], inadimplencia: [] },
    }),
  },
  loading: { type: Boolean, default: false },
});

ChartJS.register(
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Filler,
  Tooltip
);

const { formatBRL } = useChart();

const cards = computed(() => [
  {
    id: 'entradas',
    label: 'Entradas Hoje',
    value: props.data.entradas_hoje,
    variacao: props.data.entradas_variacao,
    icon: 'i-lucide-arrow-down-circle',
    color: '#10B981',
    sparkColor: '#10B981',
    sparkData: props.data.sparklines?.entradas ?? [],
  },
  {
    id: 'saidas',
    label: 'Saídas Hoje',
    value: props.data.saidas_hoje,
    variacao: props.data.saidas_variacao,
    icon: 'i-lucide-arrow-up-circle',
    color: '#EF4444',
    sparkColor: '#EF4444',
    sparkData: props.data.sparklines?.saidas ?? [],
  },
  {
    id: 'saldo',
    label: 'Saldo do Dia',
    value: props.data.saldo_dia,
    variacao: null,
    icon: 'i-lucide-landmark',
    color: '#3B82F6',
    sparkColor: '#3B82F6',
    sparkData: props.data.sparklines?.saldo ?? [],
  },
  {
    id: 'inadimplencia',
    label: 'Inadimplência Total',
    value: props.data.inadimplencia_total,
    variacao: null,
    icon: 'i-lucide-alert-circle',
    color: '#F59E0B',
    sparkColor: '#F59E0B',
    sparkData: props.data.sparklines?.inadimplencia ?? [],
  },
]);

function sparklineData(card) {
  return {
    labels: card.sparkData.map((_, i) => i),
    datasets: [
      {
        data: card.sparkData,
        borderColor: card.sparkColor,
        backgroundColor: 'transparent',
        borderWidth: 1.5,
        tension: 0.4,
        pointRadius: 0,
        fill: false,
      },
    ],
  };
}

const sparklineOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: false,
  layout: { padding: 0 },
  plugins: { legend: { display: false }, tooltip: { enabled: false } },
  scales: {
    x: { display: false },
    y: {
      display: false,
      beginAtZero: false,
      grace: '5%',
    },
  },
};

function variacaoClass(v) {
  if (v === null) return '';
  return v >= 0 ? 'kpi-badge--up' : 'kpi-badge--down';
}

function variacaoLabel(v) {
  if (v === null) return '';
  return `${v >= 0 ? '↑' : '↓'} ${Math.abs(v).toFixed(1)}%`;
}
</script>

<template>
  <div class="kpi-cards-grid">
    <template v-if="loading">
      <div v-for="n in 4" :key="n" class="kpi-card kpi-card--skeleton">
        <ChartSkeleton height="80px" :bars="4" />
      </div>
    </template>
    <template v-else>
      <div
        v-for="card in cards"
        :key="card.id"
        class="kpi-card"
        :class="[`kpi-card--${card.id}`]"
      >
        <div class="kpi-card__header">
          <i
            class="kpi-card__icon"
            :class="[card.icon]"
            :style="{ color: card.color }"
          />
          <span class="kpi-card__label">{{ card.label }}</span>
          <span
            v-if="card.variacao !== null"
            class="kpi-badge"
            :class="[variacaoClass(card.variacao)]"
          >
            {{ variacaoLabel(card.variacao) }}
          </span>
        </div>
        <div class="kpi-card__value" :style="{ color: card.color }">
          {{ formatBRL(card.value) }}
        </div>
        <div v-if="card.sparkData.length" class="kpi-card__sparkline">
          <Line :data="sparklineData(card)" :options="sparklineOptions" />
        </div>
      </div>
    </template>
  </div>
</template>
