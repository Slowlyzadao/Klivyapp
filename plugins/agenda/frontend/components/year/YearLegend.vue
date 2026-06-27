<script setup>
/**
 * YearLegend — Pequena escala de intensidade Menos → Mais.
 *
 * Render puro. Render condicional do hint à direita ("Clique em um dia
 * para ver a agenda...") só no desktop — em mobile o hint quebraria o
 * layout e a interação é óbvia (toque).
 */
import { getCurrentInstance } from 'vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const { proxy } = getCurrentInstance();
const t = proxy.$t.bind(proxy);
</script>

<template>
  <div class="yl">
    <div class="yl__scale">
      <span class="yl__caption">{{ t('AGENDA.YEAR.LEGEND.LESS') }}</span>
      <span class="yl__sq yl__sq--bucket-0" aria-hidden="true" />
      <span class="yl__sq yl__sq--bucket-1" aria-hidden="true" />
      <span class="yl__sq yl__sq--bucket-2" aria-hidden="true" />
      <span class="yl__sq yl__sq--bucket-3" aria-hidden="true" />
      <span class="yl__sq yl__sq--bucket-4" aria-hidden="true" />
      <span class="yl__caption">{{ t('AGENDA.YEAR.LEGEND.MORE') }}</span>
    </div>
    <p class="yl__hint">
      {{ t('AGENDA.YEAR.LEGEND.HINT') }}
    </p>
  </div>
</template>
