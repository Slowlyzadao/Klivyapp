<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  formatDateBR,
  formatTimeBRT,
} from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { APPOINTMENT_TYPE_LABELS } from '@plugins/patients/frontend/constants/schedule';

const props = defineProps({
  appointment: { type: Object, required: true },
  recallLoading: { type: Boolean, default: false },
});

const emit = defineEmits([
  'send-recall',
  'reschedule',
  'dismiss-forever',
  'dismiss-session',
]);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const aptTypeLabel = computed(
  () => APPOINTMENT_TYPE_LABELS[props.appointment.appointment_type] || ''
);
</script>

<template>
  <div class="sched-recall-alert mb-6">
    <div class="sched-recall-icon">
      <i class="i-lucide-bell-ring w-4 h-4" />
    </div>
    <div class="sched-recall-body">
      <h4 class="sched-recall-title">
        <i class="i-lucide-triangle-alert w-3 h-3" />
        {{ t('PATIENT_SCHEDULE.RECALL.TITLE') }}
      </h4>
      <p class="sched-recall-desc">
        {{ t('PATIENT_SCHEDULE.RECALL.DESCRIPTION_PREFIX') }}
        <strong>{{ aptTypeLabel }}</strong>
        {{ t('PATIENT_SCHEDULE.RECALL.DESCRIPTION_DATE') }}
        <strong>
          {{ formatDate(appointment.scheduled_at) }}
          {{
            t('PATIENT_SCHEDULE.RECALL.DESCRIPTION_TIME', {
              time: formatTimeBRT(appointment.scheduled_at),
            })
          }}
        </strong>
        {{ t('PATIENT_SCHEDULE.RECALL.DESCRIPTION_SUFFIX') }}
      </p>
      <div class="flex items-center gap-2">
        <BeclinicButton
          size="sm"
          variant="solid"
          color="teal"
          icon="i-ri-whatsapp-fill"
          :label="t('PATIENT_SCHEDULE.RECALL.REMIND_WHATSAPP')"
          :is-loading="recallLoading"
          :disabled="recallLoading"
          @click="emit('send-recall')"
        />
        <!-- Auditoria UX 2026-05-15: botão antes abria modal local de
             reagendamento (já removido). Agora redireciona para a agenda
             principal com o paciente pré-selecionado — secretária reagenda
             pelo calendário, source of truth única. -->
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-calendar-arrow-up"
          :label="t('PATIENT_SCHEDULE.RECALL.OPEN_AGENDA')"
          @click="emit('reschedule')"
        />
      </div>
    </div>
    <div class="sched-recall-dismiss">
      <BeclinicButton
        size="xs"
        variant="link"
        color="slate"
        :label="t('PATIENT_SCHEDULE.RECALL.DISMISS_FOREVER')"
        @click="emit('dismiss-forever')"
      />
      <BeclinicButton
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-x"
        :title="t('PATIENT_SCHEDULE.RECALL.DISMISS_TITLE')"
        @click="emit('dismiss-session')"
      />
    </div>
  </div>
</template>
