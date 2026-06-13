<script setup>
// Banner superior da tela de detalhe — paciente, status, data/duração e
// CTA "Ver Prontuário Completo". Sem CSS interno: estilos no SCSS.
import { computed } from 'vue';
import {
  STATUS_LABELS,
  formatFullDateTimeLabel,
  formatDurationMinutes,
} from './utils/formatters.js';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  detail: { type: Object, required: true },
});
const emit = defineEmits(['open-record']);

const statusLabel = computed(() =>
  STATUS_LABELS[props.detail.status] || props.detail.status || '—'
);
// Status do evento → intent do Badge padrão (beclinic_core).
const STATUS_INTENT = {
  scheduled: 'info',
  confirmed: 'info',
  arrived: 'warning',
  in_progress: 'success',
  completed: 'success',
  no_show: 'danger',
  cancelled: 'neutral',
};
const badgeIntent = computed(
  () => STATUS_INTENT[props.detail.status] || 'neutral'
);
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
        <Avatar
          :src="detail.patient?.avatar_url"
          :name="detail.patient?.name || '—'"
          :size="56"
          rounded-full
        />
        <div class="tcd-banner__patient-info">
          <div class="tcd-banner__name-row">
            <h2 class="tcd-banner__name">{{ detail.patient?.name || '—' }}</h2>
            <Badge :label="statusLabel" :intent="badgeIntent" />
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

      <BeclinicButton
        variant="solid"
        color="blue"
        label="Ver Prontuário Completo"
        :disabled="!canOpenRecord"
        @click="emit('open-record')"
      />
    </div>
  </section>
</template>
