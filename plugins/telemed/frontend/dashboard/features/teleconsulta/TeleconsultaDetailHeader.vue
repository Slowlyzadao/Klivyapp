<script setup>
// Banner superior da tela de detalhe — paciente, status, data/duração e
// CTA "Ver Prontuário Completo". Sem CSS interno: estilos no SCSS.
import { computed } from 'vue';
import {
  STATUS_LABELS,
  initialsFromName,
  formatFullDateTimeLabel,
  formatDurationMinutes,
} from './utils/formatters.js';

const props = defineProps({
  detail: { type: Object, required: true },
});
const emit = defineEmits(['open-record']);

const initials = computed(() => initialsFromName(props.detail.patient?.name));
const statusLabel = computed(() =>
  STATUS_LABELS[props.detail.status] || props.detail.status || '—'
);
const statusClass = computed(() => `tcd-status-chip tcd-status-chip--${props.detail.status}`);
const dateLabel = computed(() => formatFullDateTimeLabel(props.detail.starts_at));
const durationLabel = computed(() =>
  formatDurationMinutes(props.detail.duration_minutes)
);
const canOpenRecord = computed(() => !!props.detail.patient?.patient_id);
</script>

<template>
  <section class="tcd-banner">
    <div class="tcd-banner__row">
      <div class="tcd-banner__patient">
        <div class="tcd-banner__avatar" aria-hidden="true">{{ initials }}</div>
        <div class="tcd-banner__patient-info">
          <div class="tcd-banner__name-row">
            <h2 class="tcd-banner__name">{{ detail.patient?.name || '—' }}</h2>
            <span :class="statusClass">{{ statusLabel }}</span>
          </div>
          <p class="tcd-banner__professional">
            <i class="i-lucide-stethoscope w-3.5 h-3.5" />
            <span>{{ detail.professional?.name || '—' }}</span>
          </p>
        </div>
      </div>

      <div class="tcd-banner__divider" aria-hidden="true" />

      <div class="tcd-banner__meta">
        <span class="tcd-banner__meta-label">Data, hora e duração</span>
        <span class="tcd-banner__meta-value">
          <i class="i-lucide-calendar w-4 h-4 tcd-banner__meta-icon" />
          <span>{{ dateLabel }}</span>
          <span class="tcd-banner__meta-sep" aria-hidden="true">|</span>
          <i class="i-lucide-timer w-4 h-4 tcd-banner__meta-icon" />
          <span>{{ durationLabel }}</span>
        </span>
      </div>

      <button
        type="button"
        class="tcd-btn tcd-btn--primary tcd-btn--auto"
        :disabled="!canOpenRecord"
        @click="emit('open-record')"
      >
        Ver Prontuário Completo
      </button>
    </div>
  </section>
</template>
