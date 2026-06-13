<script setup>
/**
 * ScheduleTab — Aba "Agenda e Histórico" do prontuário do paciente.
 *
 * Orquestrador. Composição:
 *   • useAppointments — fetch + sendRecall
 *   • schedule-tab/* (sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota. Recebe `patient` para navegação
 * (passa contato/nome/telefone para a tela de Agenda) e estado inicial
 * de `recall_dismissed_at`.
 *
 * Auditoria UX 2026-05-15: ações de "Reagendar" e "Marcar Falta" foram
 * removidas da aba (decisão de produto Opção 1). Operação de agenda fica
 * exclusiva do calendário principal — elimina duplicação de código e
 * inconsistências entre AgendaEvent ↔ PatientAppointment. Esta aba vira
 * read-only para o histórico de consultas + envio de recall via WhatsApp.
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { useAppointments } from '@plugins/patients/frontend/features/patient-record/composables/useAppointments';
import { useProgressiveList } from '@plugins/patients/frontend/features/patient-record/composables/useProgressiveList';
import ScheduleHeader from '@plugins/patients/frontend/features/patient-record/components/schedule-tab/ScheduleHeader.vue';
import ScheduleKpiGrid from '@plugins/patients/frontend/features/patient-record/components/schedule-tab/ScheduleKpiGrid.vue';
import ScheduleFilters from '@plugins/patients/frontend/features/patient-record/components/schedule-tab/ScheduleFilters.vue';
import RecallAlert from '@plugins/patients/frontend/features/patient-record/components/schedule-tab/RecallAlert.vue';
import AppointmentCard from '@plugins/patients/frontend/features/patient-record/components/schedule-tab/AppointmentCard.vue';

const props = defineProps({
  patient: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const patientId = computed(() => route.params.patientId);

const {
  appointments,
  isLoading,
  isSendingRecall,
  fetch: fetchAppointments,
  sendRecall,
  dismissRecallForever: persistRecallDismiss,
} = useAppointments(patientId);

// ── UI state ────────────────────────────────────────────────
const appointmentFilter = ref('all'); // 'all' | 'upcoming' | 'issues'

const recallDismissedForever = ref(Boolean(props.patient?.recall_dismissed_at));
const recallDismissedSession = ref(false);

// ── Computeds ───────────────────────────────────────────────
const filteredAppointments = computed(() => {
  const list = appointments.value || [];
  let result;
  if (appointmentFilter.value === 'upcoming') {
    result = list.filter(a => a.is_upcoming);
  } else if (appointmentFilter.value === 'issues') {
    result = list.filter(a =>
      ['no_show', 'canceled', 'rescheduled'].includes(a.status)
    );
  } else {
    result = [...list];
  }
  // Ordenação tipo Google Calendar "Schedule": próximos no topo (ascending),
  // depois passados em descending (mais recente primeiro).
  const now = Date.now();
  return result.slice().sort((a, b) => {
    const da = new Date(a.scheduled_at || 0).getTime();
    const db = new Date(b.scheduled_at || 0).getTime();
    const aFuture = da >= now;
    const bFuture = db >= now;
    if (aFuture && !bFuture) return -1;
    if (!aFuture && bFuture) return 1;
    if (aFuture && bFuture) return da - db;
    return db - da;
  });
});

const nextAppointmentId = computed(() => {
  const upcoming = filteredAppointments.value.filter(a => a.is_upcoming);
  return upcoming.length > 0 ? upcoming[0].id : null;
});

// Auditoria UX 2026-05-15: carregamento progressivo. Lista completa vem
// da API uma vez; primeiros 30 cards renderizam imediato, próximos batches
// (30 a cada) entram via IntersectionObserver quando o sentinel aparece
// na viewport. Cobre pacientes com histórico grande (até centenas de
// consultas) sem montar todos os nodes de uma vez.
const {
  visibleItems: visibleAppointments,
  hasMore: hasMoreAppointments,
  sentinelRef: appointmentsSentinel,
} = useProgressiveList(filteredAppointments, { initialCount: 30, batchSize: 30 });

const aptKPIs = computed(() => {
  const list = appointments.value || [];
  return {
    total: list.length,
    done: list.filter(a => a.status === 'done').length,
    upcoming: list.filter(a => a.is_upcoming).length,
    noShows: list.filter(a => a.status === 'no_show').length,
  };
});

const issuesCount = computed(
  () =>
    (appointments.value || []).filter(a =>
      ['no_show', 'canceled', 'rescheduled'].includes(a.status)
    ).length
);

const pendingRecallAppointment = computed(() => {
  if (recallDismissedForever.value || recallDismissedSession.value) return null;
  return (
    (appointments.value || []).find(
      a => a.status === 'no_show' && !a.recall_sent
    ) || null
  );
});

// ── Handlers ────────────────────────────────────────────────
const handleSendRecall = () => {
  sendRecall({
    phone: props.patient?.phone_number || props.patient?.phone,
    name: props.patient?.name,
  });
};

const dismissRecallForever = () => {
  recallDismissedForever.value = true;
  persistRecallDismiss();
};

const dismissRecallSession = () => {
  recallDismissedSession.value = true;
};

const navigateToAgendaWithPatient = () => {
  router.push({
    path: `/app/accounts/${route.params.accountId}/agenda`,
    query: {
      newEvent: '1',
      contactId: props.patient?.contact_id || '',
      patientName: props.patient?.name || '',
      patientPhone: props.patient?.phone_number || props.patient?.phone || '',
      patientId: route.params.patientId,
    },
  });
};

// Auditoria UX 2026-05-15: "Reagendar pelo recall" agora apenas leva a
// secretária pra agenda principal (com paciente pré-selecionado). Antes
// abria o modal local que duplicava lógica de reagendamento. Agora há um
// único ponto de operação da agenda.
const openRescheduleFromRecall = () => {
  navigateToAgendaWithPatient();
};

onMounted(() => {
  fetchAppointments();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <ScheduleHeader
      @view-agenda="navigateToAgendaWithPatient"
      @new-appointment="navigateToAgendaWithPatient"
    />

    <ScheduleKpiGrid :kpis="aptKPIs" />

    <ScheduleFilters
      :active="appointmentFilter"
      :issues-count="issuesCount"
      @update:active="appointmentFilter = $event"
    />

    <RecallAlert
      v-if="pendingRecallAppointment"
      :appointment="pendingRecallAppointment"
      :recall-loading="isSendingRecall"
      @send-recall="handleSendRecall"
      @reschedule="openRescheduleFromRecall"
      @dismiss-forever="dismissRecallForever"
      @dismiss-session="dismissRecallSession"
    />

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-16 gap-3 text-slate-400"
    >
      <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
      <span>{{ t('PATIENT_SCHEDULE.LOADING') }}</span>
    </div>

    <div
      v-else-if="!isLoading && filteredAppointments.length === 0"
      class="sched-empty"
    >
      <div class="sched-empty-icon">
        <i class="i-lucide-calendar-off w-7 h-7" />
      </div>
      <p class="sched-empty-title">{{ t('PATIENT_SCHEDULE.EMPTY.TITLE') }}</p>
      <p class="sched-empty-hint">
        {{
          appointmentFilter === 'all'
            ? t('PATIENT_SCHEDULE.EMPTY.HINT_ALL')
            : t('PATIENT_SCHEDULE.EMPTY.HINT_FILTERED')
        }}
      </p>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-calendar-plus"
        :label="t('PATIENT_SCHEDULE.EMPTY.FIRST_APPOINTMENT')"
        class="mt-2"
        @click="navigateToAgendaWithPatient"
      />
    </div>

    <div v-else class="sched-timeline">
      <div class="sched-timeline-line" />

      <AppointmentCard
        v-for="apt in visibleAppointments"
        :key="apt.id"
        :appointment="apt"
        :is-next="apt.id === nextAppointmentId"
        :recall-loading="isSendingRecall"
        @send-recall="handleSendRecall"
      />

      <!-- Sentinel do progressive list — IntersectionObserver dispara o
           próximo batch quando esse elemento entra na viewport. -->
      <div
        v-if="hasMoreAppointments"
        ref="appointmentsSentinel"
        class="sched-load-more-sentinel"
      >
        <i class="i-lucide-loader-2 animate-spin text-slate-400 text-base" />
        <span>{{ t('PATIENT_SCHEDULE.LOADING_MORE') || 'Carregando mais…' }}</span>
      </div>

      <div v-else-if="filteredAppointments.length > 0" class="sched-timeline-end">
        <div class="sched-timeline-end-line" />
        <span class="sched-timeline-end-label">
          {{ t('PATIENT_SCHEDULE.TIMELINE.END_LABEL') }}
        </span>
        <div class="sched-timeline-end-line" />
      </div>
    </div>
  </div>
</template>
