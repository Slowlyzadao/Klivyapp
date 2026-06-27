<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  active: { type: String, default: 'all' },
});

const emit = defineEmits(['update:active']);

const { t } = useI18n();

const FILTERS = [
  { value: 'all', labelKey: 'PATIENT_TIMELINE.FILTERS.ALL', icon: 'i-lucide-layers' },
  {
    value: 'appointments',
    labelKey: 'PATIENT_TIMELINE.FILTERS.APPOINTMENTS',
    icon: 'i-lucide-calendar',
  },
  {
    value: 'clinical',
    labelKey: 'PATIENT_TIMELINE.FILTERS.CLINICAL',
    icon: 'i-lucide-stethoscope',
  },
  // Filtro `financial` removido 2026-05-24 — eventos `payment`/`refund` ficaram
  // órfãos com a depreciação do v1 (commit 9b3383a1) e o financeiro V2 não os
  // emite. Visão financeira do paciente vive na aba Financeiro do prontuário.
  {
    value: 'documents',
    labelKey: 'PATIENT_TIMELINE.FILTERS.DOCUMENTS',
    icon: 'i-lucide-file-text',
  },
];
</script>

<template>
  <div class="tl-filter-row mb-6">
    <button
      v-for="chip in FILTERS"
      :key="chip.value"
      class="tl-filter-btn"
      :class="{ 'tl-filter-btn--active': active === chip.value }"
      @click="emit('update:active', chip.value)"
    >
      <i :class="chip.icon" class="w-3.5 h-3.5" />
      {{ t(chip.labelKey) }}
    </button>
  </div>
</template>
