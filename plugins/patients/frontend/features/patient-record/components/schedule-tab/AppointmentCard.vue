<script setup>
import { useI18n } from 'vue-i18n';
import {
  formatDateBR,
  formatTimeBRT,
  formatDateTimeBRT,
} from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  EVENT_TYPE_LABELS,
  aptStatusCfg,
  priorityCfg,
} from '@plugins/patients/frontend/constants/schedule';

defineProps({
  appointment: { type: Object, required: true },
  isNext: { type: Boolean, default: false },
  recallLoading: { type: Boolean, default: false },
});

// Auditoria UX 2026-05-15: botões "Reagendar" e "Marcar Falta" removidos
// do prontuário (decisão de produto Opção 1). Operação da agenda fica
// exclusiva do calendário principal — evita duplicação que causava
// AgendaEvent/PatientAppointment divergentes. Aba "Agenda e Histórico"
// vira read-only + envio de recall (que não é operação de agenda).
const emit = defineEmits([
  'send-recall',
]);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const eventTypeLabel = apt =>
  EVENT_TYPE_LABELS[apt.event_type_label] ||
  EVENT_TYPE_LABELS[apt.appointment_type] ||
  '—';
</script>

<template>
  <div class="sched-apt-item">
    <div
      class="sched-apt-dot"
      :class="{
        'sched-apt-dot--noshow':
          appointment.status === 'no_show' || appointment.status === 'canceled',
        'sched-apt-dot--scheduled': [
          'scheduled',
          'confirmed',
          'rescheduled',
        ].includes(appointment.status),
        'sched-apt-dot--done':
          appointment.status === 'done' || appointment.status === 'completed',
      }"
    />

    <div class="sched-apt-card">
      <div class="sched-apt-header">
        <div class="sched-apt-badges">
          <span
            class="sched-status-badge"
            :class="aptStatusCfg(appointment.status).badgeCls"
          >
            <i class="w-3 h-3" :class="aptStatusCfg(appointment.status).icon" />
            {{ aptStatusCfg(appointment.status).label }}
          </span>
          <span
            v-if="
              EVENT_TYPE_LABELS[appointment.event_type_label] ||
              EVENT_TYPE_LABELS[appointment.appointment_type]
            "
            class="sched-type-badge"
          >
            {{ eventTypeLabel(appointment) }}
          </span>
          <span
            v-if="appointment.priority"
            class="sched-priority-badge"
            :class="priorityCfg(appointment.priority).cls"
          >
            {{ priorityCfg(appointment.priority).text }}
            {{ priorityCfg(appointment.priority).label }}
          </span>
          <span
            v-if="
              isNext &&
              !['canceled', 'no_show'].includes(appointment.status)
            "
            class="sched-next-badge"
          >
            <i class="i-lucide-sparkles w-2.5 h-2.5" />
            {{ t('PATIENT_SCHEDULE.CARD.NEXT_BADGE') }}
          </span>
        </div>

        <div class="sched-apt-datetime">
          <p class="sched-apt-date">
            {{ formatDate(appointment.scheduled_at) }}
          </p>
          <p class="sched-apt-time">
            {{ formatTimeBRT(appointment.scheduled_at) }} ·
            {{ appointment.duration_minutes || 60 }}{{
              t('PATIENT_SCHEDULE.CARD.DURATION_SUFFIX')
            }}
          </p>
        </div>
      </div>

      <div class="sched-apt-info">
        <div class="sched-info-col">
          <p class="sched-info-label">
            {{ t('PATIENT_SCHEDULE.CARD.PROFESSIONAL_LABEL') }}
          </p>
          <div class="flex items-center gap-2">
            <i class="i-lucide-user w-3.5 h-3.5 text-slate-500" />
            <span
              v-if="appointment.professional?.name || appointment.professional_name"
              class="sched-info-value"
            >
              {{ appointment.professional?.name || appointment.professional_name }}
            </span>
            <span v-else class="sched-info-empty">
              {{ t('PATIENT_SCHEDULE.CARD.PROFESSIONAL_FALLBACK') }}
            </span>
          </div>
        </div>
        <div v-if="appointment.treatment" class="sched-info-col">
          <p class="sched-info-label">
            {{ t('PATIENT_SCHEDULE.CARD.TREATMENT_LABEL') }}
          </p>
          <div class="flex items-center gap-2">
            <i class="i-lucide-activity w-3.5 h-3.5 text-slate-500" />
            <span class="sched-info-value">{{ appointment.treatment }}</span>
          </div>
        </div>
      </div>

      <div
        v-if="appointment.reschedule_reason"
        class="sched-reason sched-reason--amber"
      >
        <i class="i-lucide-info w-3.5 h-3.5 mt-0.5 shrink-0" />
        <span>
          <strong>{{ t('PATIENT_SCHEDULE.CARD.RESCHEDULE_REASON') }}</strong>
          {{ appointment.reschedule_reason }}
        </span>
      </div>

      <div
        v-if="appointment.cancellation_reason"
        class="sched-reason sched-reason--red"
      >
        <i class="i-lucide-circle-slash w-3.5 h-3.5 mt-0.5 shrink-0" />
        <span>
          <strong>{{ t('PATIENT_SCHEDULE.CARD.CANCELLATION_REASON') }}</strong>
          {{ appointment.cancellation_reason }}
        </span>
      </div>

      <!-- Banner soft-delete (rastreabilidade médico-legal) -->
      <div
        v-if="appointment.deleted_at"
        class="sched-reason sched-reason--red sched-reason--deleted"
      >
        <i class="i-lucide-alert-octagon w-3.5 h-3.5 mt-0.5 shrink-0" />
        <span class="flex flex-col gap-1">
          <span>
            <strong>
              {{
                appointment.deletion_reason_label ||
                t('PATIENT_SCHEDULE.CARD.DELETED_DEFAULT')
              }}
            </strong>
            <template v-if="appointment.deleted_by?.name">
              {{ t('PATIENT_SCHEDULE.CARD.DELETED_BY') }}
              <strong>{{ appointment.deleted_by.name }}</strong>
            </template>
            <template v-if="appointment.deleted_at">
              {{ t('PATIENT_SCHEDULE.CARD.DELETED_AT') }}
              <strong>{{ formatDateTimeBRT(appointment.deleted_at) }}</strong>
            </template>
          </span>
          <span v-if="appointment.deletion_note" class="sched-reason-note">
            <strong>{{ t('PATIENT_SCHEDULE.CARD.DELETION_NOTE') }}</strong>
            {{ appointment.deletion_note }}
          </span>
        </span>
      </div>

      <div v-if="appointment.notes" class="sched-notes">
        "{{ appointment.notes }}"
      </div>

      <!-- Auditoria UX 2026-05-15: botões "Reagendar" e "Marcar Falta"
           removidos. Operação de agenda agora é exclusiva do calendário
           principal — evita duplicação que causava AgendaEvent ↔
           PatientAppointment divergentes. Botão de WhatsApp recall fica
           porque não opera a agenda (só dispara mensagem para o paciente
           que faltou). -->
      <div
        v-if="appointment.status === 'no_show' && !appointment.recall_sent"
        class="sched-apt-actions"
      >
        <BeclinicButton
          size="sm"
          variant="solid"
          color="teal"
          icon="i-ri-whatsapp-fill"
          :label="t('PATIENT_SCHEDULE.CARD.NOTIFY_WHATSAPP')"
          :is-loading="recallLoading"
          :disabled="recallLoading"
          @click="emit('send-recall')"
        />
      </div>
    </div>
  </div>
</template>
