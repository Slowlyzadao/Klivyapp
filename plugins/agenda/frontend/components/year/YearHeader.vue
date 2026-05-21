<script setup>
/**
 * YearHeader — Faixa superior da Year View.
 *
 * Mostra:
 *   - Ano (título grande)
 *   - Resumo textual: "X agendamentos no ano · pico em Mês com Y"
 *   - Barras verticais: 1 por mês, altura proporcional ao max
 *
 * Render é puro: zero state local. Skeleton aparece no primeiro fetch
 * (yearTotal=0 e isLoading=true) — depois, mesmo com 0 eventos, mostra
 * o resumo "0 agendamentos no ano" sem skeleton.
 */
import { computed, getCurrentInstance } from 'vue';
import { MONTH_KEYS } from '../../utils/agenda-constants.js';

const props = defineProps({
  year: { type: Number, required: true },
  yearTotal: { type: Number, required: true },
  peakMonth: { type: Object, required: true }, // { index, count }
  monthTotals: { type: Array, required: true },
  isLoading: { type: Boolean, default: false },
});

const { proxy } = getCurrentInstance();
const t = proxy.$t.bind(proxy);

const peakMonthLabel = computed(() => {
  const idx = props.peakMonth?.index ?? 0;
  return t(`AGENDA.MONTHS.${MONTH_KEYS[idx]}`);
});

const formattedTotal = computed(() => {
  // Padrão pt-BR: 1.433 (ponto como separador de milhar)
  return new Intl.NumberFormat('pt-BR').format(props.yearTotal);
});

const barMax = computed(() => {
  let max = 0;
  for (const v of props.monthTotals) {
    if (v > max) max = v;
  }
  return max;
});

const monthShortLabels = computed(() => {
  // 3 letras + maiúsculo (Jan, Fev, ...)
  return MONTH_KEYS.map(k => {
    const full = t(`AGENDA.MONTHS.${k}`);
    return full.slice(0, 3).toUpperCase();
  });
});

function barHeight(value) {
  if (!barMax.value) return 8;
  // Faixa mínima de 8% pra manter o trilho visível mesmo em meses zerados
  const ratio = value / barMax.value;
  return Math.max(8, Math.round(ratio * 100));
}
</script>

<template>
  <header class="yh">
    <div class="yh__intro">
      <h2 class="yh__title">{{ year }}</h2>
      <p v-if="isLoading" class="yh__subtitle yh__subtitle--skeleton">
        <span class="yh__skel yh__skel--text" />
      </p>
      <p v-else class="yh__subtitle">
        <span class="yh__total">
          {{ formattedTotal }} {{ t('AGENDA.YEAR.APPOINTMENTS_IN_YEAR') }}
        </span>
        <template v-if="peakMonth.count > 0">
          <span class="yh__sep" aria-hidden="true">·</span>
          <span class="yh__peak">
            {{ t('AGENDA.YEAR.PEAK_IN') }} {{ peakMonthLabel }}
            {{ t('AGENDA.YEAR.PEAK_WITH') }} {{ peakMonth.count }}
          </span>
        </template>
      </p>
    </div>

    <ol class="yh__bars" :aria-label="t('AGENDA.YEAR.BAR_CHART_ARIA')">
      <li
        v-for="(value, idx) in monthTotals"
        :key="idx"
        class="yh__bar-item"
        :class="{ 'yh__bar-item--peak': idx === peakMonth.index && peakMonth.count > 0 }"
      >
        <span class="yh__bar-value">{{ value }}</span>
        <span
          class="yh__bar"
          :style="{ height: barHeight(value) + '%' }"
          :aria-label="`${monthShortLabels[idx]}: ${value}`"
        />
        <span class="yh__bar-label">{{ monthShortLabels[idx] }}</span>
      </li>
    </ol>
  </header>
</template>
