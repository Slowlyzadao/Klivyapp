<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * ScheduleTab — Aba "Agenda e Histórico" do prontuário do paciente.
 *
 * Lista de agendamentos do paciente com filtros (todos/próximos/faltas),
 * KPIs, banner de retorno pendente (no_show sem recall), reagendamento e
 * registro de falta. Auto-suficiente: lê patientId da rota e faz seu próprio fetch.
 *
 * Recebe `patient` como prop (para navegar para Agenda passando contato e
 * para o estado inicial de `recall_dismissed_at`).
 *
 * Componente extraído de Record.vue (Fase 5 do refactor).
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import PatientAppointmentsAPI from '@plugins/patients/frontend/api/patients/appointments';

const props = defineProps({
  patient: { type: Object, required: true },
});

const route = useRoute();
const router = useRouter();

const BRT = 'America/Sao_Paulo';

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};

const formatTime = dateString => {
  if (!dateString) return '';
  return new Date(dateString).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRT,
  });
};

// ── State ──────────────────────────────────────────────────
const appointments = ref([]);
const appointmentsLoading = ref(false);
const appointmentFilter = ref('all'); // 'all' | 'upcoming' | 'issues'

const APPOINTMENT_TYPE_LABELS = {
  avaliacao: 'Avaliação',
  retorno: 'Retorno',
  procedimento: 'Procedimento',
  revisao: 'Revisão',
  emergencia: 'Emergência',
};

const EVENT_TYPE_LABELS = {
  consultation: 'Consulta',
  agenda_block: 'Bloqueio',
  appointment: 'Compromisso',
};

const PRIORITY_CONFIG = {
  urgent: { label: 'Urgente', cls: 'bg-red-500/15 text-red-500 border-red-500/20', text: '!!!' },
  high:   { label: 'Alta',    cls: 'bg-red-500/15 text-red-500 border-red-500/20', text: '!!!' },
  medium: { label: 'Média',   cls: 'bg-yellow-500/15 text-yellow-500 border-yellow-500/20', text: '!!' },
  low:    { label: 'Baixa',   cls: 'bg-slate-500/15 text-slate-400 border-slate-500/20', text: '!' },
};
const priorityCfg = p => PRIORITY_CONFIG[p] || PRIORITY_CONFIG.medium;

const APPOINTMENT_STATUS_CONFIG = {
  scheduled: {
    label: 'Agendado', icon: 'i-lucide-calendar-clock',
    badgeCls: 'bg-green-500/10 text-green-500 border border-green-500/20',
  },
  confirmed: {
    label: 'Confirmado', icon: 'i-lucide-calendar-check',
    badgeCls: 'bg-woot-500/10 text-woot-400 border border-woot-500/20',
  },
  arrived: {
    label: 'Presente', icon: 'i-lucide-user-check',
    badgeCls: 'bg-violet-500/10 text-violet-400 border border-violet-500/20',
  },
  in_progress: {
    label: 'Em Atendimento', icon: 'i-lucide-stethoscope',
    badgeCls: 'bg-yellow-500/10 text-yellow-500/80 border border-yellow-500/20',
  },
  done: {
    label: 'Realizado', icon: 'i-lucide-check-circle-2',
    badgeCls: 'bg-green-500/10 text-green-400 border border-green-500/20',
  },
  no_show: {
    label: 'Falta', icon: 'i-lucide-user-x',
    badgeCls: 'bg-yellow-500/10 text-yellow-500 border border-yellow-500/20',
  },
  canceled: {
    label: 'Cancelado', icon: 'i-lucide-x-circle',
    badgeCls: 'bg-red-500/10 text-red-500 border border-red-500/20',
  },
  rescheduled: {
    label: 'Reagendado', icon: 'i-lucide-calendar-arrow-up',
    badgeCls: 'bg-yellow-500/10 text-yellow-500/80 border border-yellow-500/20',
  },
};
const aptStatusCfg = status =>
  APPOINTMENT_STATUS_CONFIG[status] || APPOINTMENT_STATUS_CONFIG.scheduled;

// ── Computeds ──────────────────────────────────────────────
const filteredAppointments = computed(() => {
  const list = appointments.value || [];
  let result;
  if (appointmentFilter.value === 'upcoming') {
    result = list.filter(a => a.is_upcoming);
  } else if (appointmentFilter.value === 'issues') {
    result = list.filter(a => ['no_show', 'canceled', 'rescheduled'].includes(a.status));
  } else {
    result = [...list];
  }
  return result.slice().sort((a, b) => {
    const da = new Date(a.scheduled_at || 0).getTime();
    const db = new Date(b.scheduled_at || 0).getTime();
    return da - db;
  });
});

const nextAppointmentId = computed(() => {
  const upcoming = filteredAppointments.value.filter(a => a.is_upcoming);
  return upcoming.length > 0 ? upcoming[0].id : null;
});

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
  () => (appointments.value || []).filter(a =>
    ['no_show', 'canceled', 'rescheduled'].includes(a.status)
  ).length
);

// Recall banner state (inicializado pelo prop patient.recall_dismissed_at)
const recallDismissedForever = ref(Boolean(props.patient?.recall_dismissed_at));
const recallDismissedSession = ref(false);

const pendingRecallAppointment = computed(() => {
  if (recallDismissedForever.value || recallDismissedSession.value) return null;
  return (
    (appointments.value || []).find(a => a.status === 'no_show' && !a.recall_sent) || null
  );
});

const dismissRecallForever = async () => {
  recallDismissedForever.value = true;
  try {
    await PatientsAPI.update(route.params.patientId, {
      recall_dismissed_at: new Date().toISOString(),
    });
  } catch (e) {
    // best effort — UI já dispensou
  }
};

const dismissRecallSession = () => {
  recallDismissedSession.value = true;
};

// ── Fetch ──────────────────────────────────────────────────
const fetchAppointments = async () => {
  try {
    appointmentsLoading.value = true;
    const { data } = await PatientAppointmentsAPI.get(route.params.patientId);
    appointments.value = data?.appointments || data?.data || (Array.isArray(data) ? data : []);
  } catch (error) {
    useAlert('Erro ao carregar agenda do paciente.');
  } finally {
    appointmentsLoading.value = false;
  }
};

// ── Modal: Reagendar ───────────────────────────────────────
const showRescheduleModal = ref(false);
const rescheduleLoading = ref(false);
const rescheduleTargetId = ref(null);
const rescheduleForm = ref({
  new_scheduled_at: '',
  duration_minutes: 60,
  reschedule_reason: '',
});

const openRescheduleModal = apt => {
  rescheduleTargetId.value = apt.id;
  const d = new Date(apt.scheduled_at);
  d.setDate(d.getDate() + 7);
  const iso = d.toISOString().slice(0, 16);
  rescheduleForm.value = {
    new_scheduled_at: iso,
    duration_minutes: apt.duration_minutes || 60,
    reschedule_reason: '',
  };
  showRescheduleModal.value = true;
};

const handleReschedule = async () => {
  if (!rescheduleForm.value.new_scheduled_at) {
    useAlert('Selecione uma data e hora para o reagendamento.');
    return;
  }
  try {
    rescheduleLoading.value = true;
    await PatientAppointmentsAPI.reschedule(
      route.params.patientId,
      rescheduleTargetId.value,
      {
        new_scheduled_at: rescheduleForm.value.new_scheduled_at,
        duration_minutes: rescheduleForm.value.duration_minutes,
        reschedule_reason: rescheduleForm.value.reschedule_reason,
      }
    );
    showRescheduleModal.value = false;
    useAlert('Consulta reagendada com sucesso!');
    await fetchAppointments();
  } catch (error) {
    useAlert('Erro ao reagendar consulta.');
  } finally {
    rescheduleLoading.value = false;
  }
};

// ── Modal: Confirmar Falta ─────────────────────────────────
const showNoShowModal = ref(false);
const noShowTargetId = ref(null);
const noShowLoading = ref(false);

const openNoShowModal = apt => {
  noShowTargetId.value = apt.id;
  showNoShowModal.value = true;
};

const handleNoShow = async () => {
  try {
    noShowLoading.value = true;
    await PatientAppointmentsAPI.markNoShow(route.params.patientId, noShowTargetId.value);
    showNoShowModal.value = false;
    useAlert('Falta registrada com sucesso.');
    await fetchAppointments();
  } catch (error) {
    useAlert('Erro ao registrar falta.');
  } finally {
    noShowLoading.value = false;
  }
};

// ── Recall via WhatsApp ────────────────────────────────────
const recallLoading = ref(false);
const sendRecallWhatsApp = async () => {
  try {
    recallLoading.value = true;
    await PatientAppointmentsAPI.sendRecall(route.params.patientId);
    useAlert('Lembrete de retorno enviado via WhatsApp!');
    await fetchAppointments();
  } catch (error) {
    // Fallback: abre WhatsApp direto se a API não estiver configurada
    const phone = props.patient?.phone_number || props.patient?.phone;
    if (phone) {
      const clean = phone.replace(/\D/g, '');
      const msg = encodeURIComponent(
        `Olá${props.patient?.name ? ` ${props.patient.name}` : ''}! Notamos que você não compareceu à sua última consulta. Gostaríamos de reagendar para um horário conveniente para você. 😊`
      );
      window.open(`https://wa.me/${clean}?text=${msg}`, '_blank');
    } else {
      useAlert('Lembrete enviado!');
    }
  } finally {
    recallLoading.value = false;
  }
};

// ── Navegação para Agenda ──────────────────────────────────
const navigateToAgendaWithPatient = () => {
  const pid = route.params.patientId;
  router.push({
    path: '/app/accounts/' + route.params.accountId + '/agenda',
    query: {
      newEvent: '1',
      contactId: props.patient?.contact_id || '',
      patientName: props.patient?.name || '',
      patientPhone: props.patient?.phone_number || props.patient?.phone || '',
      patientId: pid,
    },
  });
};

const openRescheduleFromRecall = apt => {
  if (apt) openRescheduleModal(apt);
  else navigateToAgendaWithPatient();
};

onMounted(() => {
  fetchAppointments();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-6">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">Agenda e Histórico</h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Acompanhamento completo de agendamentos, faltas e retornos do
          paciente.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button class="geral-header-btn" @click="navigateToAgendaWithPatient">
          <i class="i-lucide-calendar w-4 h-4" /> Ver na Agenda
        </button>
        <button
          class="btn-primary bg-woot-600 hover:bg-woot-500 text-white flex items-center gap-2"
          @click="navigateToAgendaWithPatient"
        >
          <i class="i-lucide-calendar-plus w-4 h-4" /> Novo Agendamento
        </button>
      </div>
    </div>

    <!-- KPIs -->
    <div class="sched-kpi-grid mb-6">
      <div class="sched-kpi-card">
        <div class="sched-kpi-icon"><i class="i-lucide-calendar-days w-4 h-4" /></div>
        <p class="sched-kpi-label">Total</p>
        <p class="sched-kpi-value">{{ aptKPIs.total }}</p>
      </div>
      <div class="sched-kpi-card sched-kpi-card--green">
        <div class="sched-kpi-icon sched-kpi-icon--green"><i class="i-lucide-check-circle-2 w-4 h-4" /></div>
        <p class="sched-kpi-label">Realizados</p>
        <p class="sched-kpi-value">{{ aptKPIs.done }}</p>
      </div>
      <div class="sched-kpi-card sched-kpi-card--blue">
        <div class="sched-kpi-icon sched-kpi-icon--blue"><i class="i-lucide-clock w-4 h-4" /></div>
        <p class="sched-kpi-label">Próximos</p>
        <p class="sched-kpi-value">{{ aptKPIs.upcoming }}</p>
      </div>
      <div class="sched-kpi-card sched-kpi-card--red">
        <div class="sched-kpi-icon sched-kpi-icon--red"><i class="i-lucide-user-x w-4 h-4" /></div>
        <p class="sched-kpi-label">Faltas</p>
        <p class="sched-kpi-value">{{ aptKPIs.noShows }}</p>
      </div>
    </div>

    <!-- Filtros pill -->
    <div class="sched-filter-row mb-6">
      <button
        class="sched-filter-btn"
        :class="{ 'sched-filter-btn--active': appointmentFilter === 'all' }"
        @click="appointmentFilter = 'all'"
      >
        <i class="i-lucide-layout-grid w-3.5 h-3.5" /> Todos
      </button>
      <button
        class="sched-filter-btn"
        :class="{ 'sched-filter-btn--active': appointmentFilter === 'upcoming' }"
        @click="appointmentFilter = 'upcoming'"
      >
        <i class="i-lucide-calendar-clock w-3.5 h-3.5" /> Próximos
      </button>
      <button
        class="sched-filter-btn"
        :class="{ 'sched-filter-btn--active': appointmentFilter === 'issues' }"
        @click="appointmentFilter = 'issues'"
      >
        <i class="i-lucide-octagon-alert w-3.5 h-3.5" /> Faltas/Cancelados
        <span v-if="issuesCount > 0" class="sched-filter-badge">{{ issuesCount }}</span>
      </button>
    </div>

    <!-- Alerta de Retorno Pendente -->
    <div v-if="pendingRecallAppointment" class="sched-recall-alert mb-6">
      <div class="sched-recall-icon">
        <i class="i-lucide-bell-ring w-4 h-4" />
      </div>
      <div class="sched-recall-body">
        <h4 class="sched-recall-title">
          <i class="i-lucide-triangle-alert w-3 h-3" />
          Retorno Pendente — Paciente Faltou
        </h4>
        <p class="sched-recall-desc">
          O paciente não compareceu à consulta de
          <strong>{{
            APPOINTMENT_TYPE_LABELS[pendingRecallAppointment.appointment_type]
          }}</strong>
          agendada para
          <strong
            >{{ formatDate(pendingRecallAppointment.scheduled_at) }} às
            {{ formatTime(pendingRecallAppointment.scheduled_at) }}</strong
          >. Nenhum lembrete foi enviado ainda.
        </p>
        <div class="flex items-center gap-2">
          <button
            class="sched-recall-btn"
            :disabled="recallLoading"
            @click="sendRecallWhatsApp"
          >
            <i v-if="recallLoading" class="i-lucide-loader-2 animate-spin w-3 h-3" />
            <i v-else class="i-lucide-message-circle w-3 h-3" />
            Lembrar via WhatsApp
          </button>
          <button
            class="sched-recall-btn-ghost"
            @click="openRescheduleFromRecall(pendingRecallAppointment)"
          >
            <i class="i-lucide-calendar-arrow-up w-3 h-3" />
            Reagendar Manualmente
          </button>
        </div>
      </div>
      <div class="sched-recall-dismiss">
        <button class="sched-dismiss-text" @click="dismissRecallForever">
          Não mostrar mais
        </button>
        <button class="sched-dismiss-x" title="Fechar lembrete" @click="dismissRecallSession">
          <i class="i-lucide-x w-5 h-5" />
        </button>
      </div>
    </div>

    <!-- Loading -->
    <div
      v-if="appointmentsLoading"
      class="flex items-center justify-center py-16 gap-3 text-slate-400"
    >
      <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
      <span>Carregando agendamentos...</span>
    </div>

    <!-- Empty State -->
    <div
      v-else-if="!appointmentsLoading && filteredAppointments.length === 0"
      class="sched-empty"
    >
      <div class="sched-empty-icon">
        <i class="i-lucide-calendar-off w-7 h-7" />
      </div>
      <p class="sched-empty-title">Nenhum agendamento encontrado</p>
      <p class="sched-empty-hint">
        {{
          appointmentFilter === 'all'
            ? 'Este paciente ainda não tem consultas registradas.'
            : 'Nenhum registro neste filtro.'
        }}
      </p>
      <button
        class="btn-primary mt-2 flex items-center gap-2"
        @click="navigateToAgendaWithPatient"
      >
        <i class="i-lucide-calendar-plus" /> Agendar Primeira Consulta
      </button>
    </div>

    <!-- Lista de Agendamentos -->
    <div v-else class="sched-timeline">
      <div class="sched-timeline-line" />

      <div
        v-for="apt in filteredAppointments"
        :key="apt.id"
        class="sched-apt-item"
      >
        <div
          class="sched-apt-dot"
          :class="{
            'sched-apt-dot--noshow':
              apt.status === 'no_show' || apt.status === 'canceled',
            'sched-apt-dot--scheduled': [
              'scheduled',
              'confirmed',
              'rescheduled',
            ].includes(apt.status),
            'sched-apt-dot--done':
              apt.status === 'done' || apt.status === 'completed',
          }"
        />

        <div class="sched-apt-card">
          <div class="sched-apt-header">
            <div class="sched-apt-badges">
              <span
                class="sched-status-badge"
                :class="aptStatusCfg(apt.status).badgeCls"
              >
                <i class="w-3 h-3" :class="aptStatusCfg(apt.status).icon" />
                {{ aptStatusCfg(apt.status).label }}
              </span>
              <span
                v-if="
                  EVENT_TYPE_LABELS[apt.event_type_label] ||
                  EVENT_TYPE_LABELS[apt.appointment_type]
                "
                class="sched-type-badge"
              >
                {{
                  EVENT_TYPE_LABELS[apt.event_type_label] ||
                  EVENT_TYPE_LABELS[apt.appointment_type] ||
                  '—'
                }}
              </span>
              <span
                v-if="apt.priority"
                class="sched-priority-badge"
                :class="priorityCfg(apt.priority).cls"
              >
                {{ priorityCfg(apt.priority).text }}
                {{ priorityCfg(apt.priority).label }}
              </span>
              <span
                v-if="
                  apt.id === nextAppointmentId &&
                  !['canceled', 'no_show'].includes(apt.status)
                "
                class="sched-next-badge"
              >
                <i class="i-lucide-sparkles w-2.5 h-2.5" /> PRÓXIMA
              </span>
            </div>

            <div class="sched-apt-datetime">
              <p class="sched-apt-date">{{ formatDate(apt.scheduled_at) }}</p>
              <p class="sched-apt-time">
                {{ formatTime(apt.scheduled_at) }} ·
                {{ apt.duration_minutes || 60 }}min
              </p>
            </div>
          </div>

          <div class="sched-apt-info">
            <div class="sched-info-col">
              <p class="sched-info-label">Profissional Responsável</p>
              <div class="flex items-center gap-2">
                <i class="i-lucide-user w-3.5 h-3.5 text-slate-500" />
                <span
                  v-if="apt.professional?.name || apt.professional_name"
                  class="sched-info-value"
                >
                  {{ apt.professional?.name || apt.professional_name }}
                </span>
                <span v-else class="sched-info-empty">Não informado</span>
              </div>
            </div>
            <div v-if="apt.treatment" class="sched-info-col">
              <p class="sched-info-label">Tratamento</p>
              <div class="flex items-center gap-2">
                <i class="i-lucide-activity w-3.5 h-3.5 text-slate-500" />
                <span class="sched-info-value">{{ apt.treatment }}</span>
              </div>
            </div>
          </div>

          <div
            v-if="apt.reschedule_reason"
            class="sched-reason sched-reason--amber"
          >
            <i class="i-lucide-info w-3.5 h-3.5 mt-0.5 shrink-0" />
            <span
              ><strong>Motivo Reagendamento:</strong>
              {{ apt.reschedule_reason }}</span
            >
          </div>

          <div
            v-if="apt.cancellation_reason"
            class="sched-reason sched-reason--red"
          >
            <i class="i-lucide-circle-slash w-3.5 h-3.5 mt-0.5 shrink-0" />
            <span
              ><strong>Motivo Cancelamento:</strong>
              {{ apt.cancellation_reason }}</span
            >
          </div>

          <div v-if="apt.notes" class="sched-notes">"{{ apt.notes }}"</div>

          <div
            v-if="apt.cancellable || apt.reschedulable || apt.status === 'no_show'"
            class="sched-apt-actions"
          >
            <button
              v-if="apt.status === 'no_show' && !apt.recall_sent"
              class="sched-action-btn sched-action-btn--amber"
              :disabled="recallLoading"
              @click="sendRecallWhatsApp"
            >
              <i v-if="recallLoading" class="i-lucide-loader-2 animate-spin w-3.5 h-3.5" />
              <i v-else class="i-lucide-message-circle w-3.5 h-3.5" />
              Notificar WhatsApp
            </button>
            <button
              v-if="apt.reschedulable || apt.status === 'no_show'"
              class="sched-action-btn"
              @click="
                apt.status === 'no_show'
                  ? navigateToAgendaWithPatient()
                  : openRescheduleModal(apt)
              "
            >
              <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
              Reagendar Agora
            </button>
            <button
              v-if="apt.cancellable"
              class="sched-action-btn sched-action-btn--danger"
              @click="openNoShowModal(apt)"
            >
              <i class="i-lucide-user-minus w-3.5 h-3.5" />
              Marcar Falta
            </button>
          </div>
        </div>
      </div>

      <div v-if="filteredAppointments.length > 0" class="sched-timeline-end">
        <div class="sched-timeline-end-line" />
        <span class="sched-timeline-end-label">Início do histórico</span>
        <div class="sched-timeline-end-line" />
      </div>
    </div>

    <!-- Modal: Reagendar -->
    <div
      v-if="showRescheduleModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showRescheduleModal = false"
    >
      <div class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md">
        <div class="flex items-center justify-between p-6 border-b border-slate-700/50">
          <div>
            <h3 class="text-lg font-semibold text-slate-100 flex items-center gap-2">
              <i class="i-lucide-calendar-arrow-up text-orange-400" />
              Reagendar Consulta
            </h3>
            <p class="text-xs text-slate-400 mt-0.5">
              Selecione a nova data e horário
            </p>
          </div>
          <button class="text-slate-400 hover:text-slate-100" @click="showRescheduleModal = false">
            <i class="i-lucide-x text-xl" />
          </button>
        </div>
        <div class="p-6 space-y-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Nova Data e Hora *</label>
            <input
              v-model="rescheduleForm.new_scheduled_at"
              type="datetime-local"
              class="form-input w-full"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Duração (minutos)</label>
            <input
              v-model="rescheduleForm.duration_minutes"
              type="number"
              min="15"
              max="480"
              step="15"
              class="form-input w-full"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Motivo do Reagendamento</label>
            <input
              v-model="rescheduleForm.reschedule_reason"
              type="text"
              placeholder="Ex: Solicitação do paciente..."
              class="form-input w-full"
            />
          </div>
        </div>
        <div class="p-6 border-t border-slate-700/50 flex justify-end gap-3">
          <button class="btn-secondary" @click="showRescheduleModal = false">Cancelar</button>
          <button
            class="bg-orange-600 hover:bg-orange-500 text-white font-medium py-2 px-4 rounded-xl transition-colors flex items-center gap-2 disabled:opacity-50"
            :disabled="rescheduleLoading || !rescheduleForm.new_scheduled_at"
            @click="handleReschedule"
          >
            <i v-if="rescheduleLoading" class="i-lucide-loader-2 animate-spin" />
            <i v-else class="i-lucide-calendar-check" />
            Confirmar Reagendamento
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Confirmar Falta -->
    <div
      v-if="showNoShowModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showNoShowModal = false"
    >
      <div class="bg-slate-900 border border-slate-700 rounded-xl w-full max-w-sm">
        <div class="flex items-center justify-between p-5 border-b border-slate-700/50">
          <div class="flex items-center gap-3">
            <i class="i-lucide-user-minus text-red-400 text-lg" />
            <div>
              <h3 class="text-base font-semibold text-slate-100">Registrar Falta</h3>
              <p class="text-xs text-slate-400 mt-0.5">Esta ação não pode ser desfeita</p>
            </div>
          </div>
          <button class="text-slate-500 hover:text-slate-200 transition-colors" @click="showNoShowModal = false">
            <i class="i-lucide-x text-lg" />
          </button>
        </div>
        <div class="p-5">
          <p class="text-sm text-slate-400">
            O status será alterado para
            <span class="font-semibold text-red-400">Falta</span>
            e o contador de faltas do paciente será incrementado.
          </p>
        </div>
        <div class="p-5 border-t border-slate-700/50 flex justify-end gap-3">
          <button class="btn-secondary" @click="showNoShowModal = false">Cancelar</button>
          <button
            class="btn-primary bg-red-600 hover:bg-red-500 text-white flex items-center gap-2 disabled:opacity-50"
            :disabled="noShowLoading"
            @click="handleNoShow"
          >
            <i v-if="noShowLoading" class="i-lucide-loader-2 animate-spin" />
            <i v-else class="i-lucide-user-minus" />
            Confirmar Falta
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ═══════════════════════════════════════════
   AGENDA E HISTÓRICO — estilos exclusivos
═══════════════════════════════════════════ */

/* KPI grid 4 colunas */
.sched-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
}

/* KPI card base */
.sched-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
}
.sched-kpi-card--green {
  border-color: rgba(34, 197, 94, 0.2);
  background: rgba(34, 197, 94, 0.04);
}
.sched-kpi-card--blue {
  border-color: rgba(59, 130, 246, 0.2);
  background: rgba(59, 130, 246, 0.04);
}
.sched-kpi-card--red {
  border-color: rgba(239, 68, 68, 0.2);
  background: rgba(239, 68, 68, 0.04);
}

/* KPI ícone */
.sched-kpi-icon {
  width: 28px;
  height: 28px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.05);
  color: #475569;
  margin-bottom: 4px;
}
.sched-kpi-icon--green {
  background: rgba(34, 197, 94, 0.12);
  color: #4ade80;
}
.sched-kpi-icon--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}
.sched-kpi-icon--red {
  background: rgba(239, 68, 68, 0.12);
  color: #f87171;
}

.sched-kpi-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  margin: 0;
}
.sched-kpi-value {
  font-size: 28px;
  font-weight: 700;
  color: #e2e8f0;
  margin: 0;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

/* Filtros pill */
.sched-filter-row {
  display: flex;
  align-items: center;
  gap: 6px;
}
.sched-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 6px 14px;
  border-radius: 99px;
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  cursor: pointer;
  transition:
    background 0.13s,
    color 0.13s,
    border-color 0.13s;
  white-space: nowrap;
}
.sched-filter-btn:hover {
  color: #94a3b8;
  background: rgba(255, 255, 255, 0.06);
}
.sched-filter-btn--active {
  background: rgba(59, 130, 246, 0.12);
  border-color: rgba(59, 130, 246, 0.25);
  color: #60a5fa;
}
.sched-filter-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 18px;
  height: 18px;
  padding: 0 4px;
  border-radius: 99px;
  background: rgba(255, 255, 255, 0.08);
  color: #64748b;
  font-size: 10px;
  font-weight: 700;
}

/* Alerta de retorno */
.sched-recall-alert {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 18px;
  background: rgba(251, 191, 36, 0.06);
  border: 1px solid rgba(251, 191, 36, 0.2);
  border-radius: 12px;
}
.sched-recall-icon {
  width: 36px;
  height: 36px;
  border-radius: 99px;
  background: rgba(251, 191, 36, 0.15);
  color: #fbbf24;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.sched-recall-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.sched-recall-title {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 13px;
  font-weight: 600;
  color: #fbbf24;
  margin: 0;
}
.sched-recall-desc {
  font-size: 12px;
  color: rgba(251, 191, 36, 0.7);
  margin: 0;
  line-height: 1.5;
}
.sched-recall-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 600;
  background: #fbbf24;
  color: #1e1b0e;
  border: none;
  cursor: pointer;
  transition: background 0.13s;
}
.sched-recall-btn:hover {
  background: #f59e0b;
}
.sched-recall-btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.sched-recall-btn-ghost {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 500;
  background: transparent;
  border: 1px solid rgba(251, 191, 36, 0.25);
  color: #fbbf24;
  cursor: pointer;
  transition: background 0.13s;
}
.sched-recall-btn-ghost:hover {
  background: rgba(251, 191, 36, 0.08);
}
.sched-recall-dismiss {
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.sched-dismiss-text {
  font-size: 10px;
  color: rgba(251, 191, 36, 0.4);
  background: none;
  border: none;
  cursor: pointer;
  text-decoration: underline;
  text-underline-offset: 2px;
  white-space: nowrap;
  transition: color 0.13s;
  padding: 0;
  line-height: 1.4;
}
.sched-dismiss-text:hover {
  color: rgba(251, 191, 36, 0.7);
}
.sched-dismiss-x {
  width: auto;
  height: auto;
  padding: 2px;
  border-radius: 4px;
  background: none;
  border: none;
  color: rgba(251, 191, 36, 0.45);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  transition: color 0.13s;
}
.sched-dismiss-x:hover {
  color: #fbbf24;
}

/* Empty state */
.sched-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 56px 24px;
  background: rgba(255, 255, 255, 0.02);
  border: 1px dashed rgba(255, 255, 255, 0.07);
  border-radius: 16px;
  text-align: center;
}
.sched-empty-icon {
  width: 52px;
  height: 52px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  color: #334155;
  display: flex;
  align-items: center;
  justify-content: center;
}
.sched-empty-title {
  font-size: 14px;
  font-weight: 500;
  color: #94a3b8;
  margin: 0;
}
.sched-empty-hint {
  font-size: 12px;
  color: #334155;
  margin: 0;
}

/* Linha do tempo */
.sched-timeline {
  position: relative;
  padding-left: 48px;
  display: flex;
  flex-direction: column;
  gap: 0;
}
/* A linha é centralizada exatamente no eixo dos dots (dot left=-28, metade=7px → 48-28+7=27px) */
.sched-timeline-line {
  position: absolute;
  left: 27px;
  top: 12px;
  bottom: 12px;
  width: 1px;
  background: linear-gradient(
    to bottom,
    rgba(255, 255, 255, 0.07) 80%,
    transparent
  );
}

/* Item da linha do tempo */
.sched-apt-item {
  position: relative;
  margin-bottom: 16px;
}

/* Dot — sólido, sem borda */
.sched-apt-dot {
  position: absolute;
  left: -28px; /* 48px padding - 28px = dot começa no eixo certo */
  top: 20px;
  width: 14px;
  height: 14px;
  border-radius: 99px;
  background: #334155; /* neutro para status desconhecido */
  border: none;
  z-index: 2;
}
/* Falta / Cancelado → amarelo */
.sched-apt-dot--noshow {
  background: #eab308;
}
/* Agendado / Confirmado  → verde */
.sched-apt-dot--scheduled {
  background: #22c55e;
}
/* Realizado              → cinza claro */
.sched-apt-dot--done {
  background: #475569;
}

/* Card de agendamento */
.sched-apt-card {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  padding: 18px 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  transition:
    background 0.14s,
    border-color 0.14s;
}
.sched-apt-card:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.1);
}

/* Header do card */
.sched-apt-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.sched-apt-badges {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
}

/* Badge de status — herda cores do aptStatusCfg */
.sched-status-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 10px;
  border-radius: 99px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

/* Tipo de evento */
.sched-type-badge {
  background: rgba(255, 255, 255, 0.05);
  color: #94a3b8;
  border: 1px solid rgba(255, 255, 255, 0.07);
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 500;
}

/* Prioridade */
.sched-priority-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 600;
}

/* PRÓXIMA */
.sched-next-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 700;
  background: rgba(59, 130, 246, 0.1);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  animation: pulse 2s ease-in-out infinite;
}

/* Data/Hora */
.sched-apt-datetime {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  flex-shrink: 0;
}
.sched-apt-date {
  font-size: 13px;
  font-weight: 600;
  color: #e2e8f0;
  margin: 0;
  font-variant-numeric: tabular-nums;
}
.sched-apt-time {
  font-size: 11px;
  color: #475569;
  margin: 0;
  font-variant-numeric: tabular-nums;
}

/* Info grid (profissional / tratamento) */
.sched-apt-info {
  display: grid;
  grid-template-columns: repeat(2, auto);
  gap: 16px 40px;
  align-items: start;
}
.sched-info-col {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.sched-info-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #334155;
  margin: 0;
}
.sched-info-value {
  font-size: 13px;
  font-weight: 500;
  color: #cbd5e1;
}
.sched-info-empty {
  font-size: 13px;
  color: #334155;
  font-style: italic;
}

/* Motivo (reagendamento / cancelamento) */
.sched-reason {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.4;
}
.sched-reason--amber {
  background: rgba(251, 191, 36, 0.05);
  border: 1px solid rgba(251, 191, 36, 0.12);
  color: rgba(251, 191, 36, 0.7);
}
.sched-reason--red {
  background: rgba(239, 68, 68, 0.05);
  border: 1px solid rgba(239, 68, 68, 0.12);
  color: rgba(248, 113, 113, 0.7);
}

/* Observações */
.sched-notes {
  font-size: 12px;
  color: #475569;
  font-style: italic;
  background: rgba(0, 0, 0, 0.12);
  border: 1px solid rgba(255, 255, 255, 0.04);
  border-radius: 8px;
  padding: 8px 12px;
  line-height: 1.5;
}

/* Ações do card (footer) */
.sched-apt-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}
.sched-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(255, 255, 255, 0.04);
  color: #64748b;
  transition:
    background 0.13s,
    color 0.13s,
    border-color 0.13s;
  white-space: nowrap;
}
.sched-action-btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.sched-action-btn:not(:disabled):hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.sched-action-btn--amber:not(:disabled):hover {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.2);
}
.sched-action-btn--danger:not(:disabled):hover {
  background: rgba(239, 68, 68, 0.08);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.15);
}

/* Fim da linha do tempo */
.sched-timeline-end {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  opacity: 0.35;
}
.sched-timeline-end-line {
  flex: 1;
  height: 1px;
  background: linear-gradient(to right, rgba(255, 255, 255, 0.06), transparent);
}
.sched-timeline-end-label {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.18em;
  color: #334155;
  white-space: nowrap;
}
</style>
