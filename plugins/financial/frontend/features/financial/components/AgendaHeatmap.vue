<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';
import { useFormatCurrency } from '../composables/useFormatCurrency';

const props = defineProps({
  data: {
    type: Object,
    default: () => ({ matrix: [], days: [], slots: [], peak: {} }),
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const { formatCurrency } = useFormatCurrency();

const isEmpty = computed(() => {
  return !props.data || !props.data.matrix || props.data.matrix.length === 0;
});

const corCelula = pct => {
  if (pct === 0) return 'var(--heatmap-0, rgb(var(--s-100)))';
  if (pct < 25) return 'var(--heatmap-25, #DBEAFE)';
  if (pct < 50) return 'var(--heatmap-50, #BFDBFE)';
  if (pct < 75) return 'var(--heatmap-75, #60A5FA)';
  return 'var(--heatmap-100, #2563EB)';
};

// Tooltip helpers (poderia usar v-tooltip)
const getTooltipTitle = (day, slot, cell) => {
  return `${day} ${slot}\nAgendamentos: ${cell.agendamentos}\nOcupação: ${cell.ocupacao_pct}%\nTicketMédio: ${formatCurrency(cell.receita_media)}`;
};
</script>

<template>
  <div class="heatmap-wrapper">
    <template v-if="loading">
      <ChartSkeleton height="260px" />
    </template>
    <template v-else-if="isEmpty">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div v-if="data.peak && data.peak.pct > 0" class="heatmap-info">
        <i class="i-lucide-info" />
        {{ t('FINANCIAL.CHARTS.HEATMAP.PEAK') }}
        <strong>{{ data.peak.day }} {{ t('FINANCIAL.CHARTS.HEATMAP.AT') }}
          {{ data.peak.slot }}</strong>
        ({{ data.peak.pct }}%)
      </div>

      <div class="heatmap-container">
        <!-- Header (Dias da semana) -->
        <div class="heatmap-grid heatmap-grid--header">
          <div class="heatmap-axis" />
          <!-- edge vazio -->
          <div v-for="day in data.days" :key="day" class="heatmap-col-header">
            {{ day.substring(0, 3) }}
          </div>
        </div>

        <!-- Body (Horas x Dias) -->
        <div class="heatmap-body">
          <div
            v-for="(slotData, sIdx) in data.matrix"
            :key="sIdx"
            class="heatmap-grid"
          >
            <div class="heatmap-row-header">{{ data.slots[sIdx] }}</div>
            <div
              v-for="(cell, dIdx) in slotData"
              :key="dIdx"
              class="heatmap-cell"
              :style="{ backgroundColor: corCelula(cell.ocupacao_pct) }"
              :title="getTooltipTitle(data.days[dIdx], data.slots[sIdx], cell)"
            >
              <span class="sr-only">{{ cell.ocupacao_pct }}%</span>
            </div>
          </div>
        </div>

        <!-- Legenda -->
        <div class="heatmap-legend">
          <span>{{ t('FINANCIAL.CHARTS.HEATMAP.LESS') }}</span>
          <div class="heatmap-legend__box heatmap-legend__box--0" />
          <div class="heatmap-legend__box heatmap-legend__box--25" />
          <div class="heatmap-legend__box heatmap-legend__box--50" />
          <div class="heatmap-legend__box heatmap-legend__box--75" />
          <div class="heatmap-legend__box heatmap-legend__box--100" />
          <span>{{ t('FINANCIAL.CHARTS.HEATMAP.MORE') }}</span>
        </div>
      </div>
    </template>
  </div>
</template>
