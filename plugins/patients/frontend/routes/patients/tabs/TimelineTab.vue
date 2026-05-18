<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * TimelineTab — Aba "Timeline" do prontuário do paciente.
 *
 * Visão consolidada de eventos (consultas, prontuários, financeiro, documentos)
 * agrupados por data, com filtros e ordenação. Auto-suficiente: lê patientId
 * da rota e faz seu próprio fetch.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor — ver CHANGELOG e
 * docs/03-engineering/audit-exames-imagens.md para o padrão).
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import PatientTimelineAPI from '@plugins/patients/frontend/api/patients/patientTimeline';

const route = useRoute();

const BRT = 'America/Sao_Paulo';

const formatTime = dateString => {
  if (!dateString) return '';
  return new Date(dateString).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRT,
  });
};

// ── State ──────────────────────────────────────────────────
const timelineEvents = ref([]);
const timelineLoading = ref(false);
const timelineFilter = ref('all');
const timelineFilterOpen = ref(false);
const timelineSortOrder = ref('newest'); // 'newest' | 'oldest'

// ── Configurações de tipo de evento ────────────────────────
const TIMELINE_TYPE_CONFIG = {
  cadastro: { icon: 'i-lucide-user-plus', color: 'indigo', label: 'Cadastro' },
  anamnesis_filled: {
    icon: 'i-lucide-clipboard-list',
    color: 'blue',
    label: 'Anamnese',
  },
  appointment_scheduled: {
    icon: 'i-lucide-calendar-plus',
    color: 'orange',
    label: 'Agendamento',
  },
  appointment_rescheduled: {
    icon: 'i-lucide-calendar-clock',
    color: 'yellow',
    label: 'Reagendamento',
  },
  appointment_done: {
    icon: 'i-lucide-calendar-check',
    color: 'emerald',
    label: 'Consulta Realizada',
  },
  appointment_no_show: {
    icon: 'i-lucide-user-x',
    color: 'red',
    label: 'Falta',
  },
  appointment_canceled: {
    icon: 'i-lucide-calendar-x',
    color: 'rose',
    label: 'Cancelamento',
  },
  clinical_note: {
    icon: 'i-lucide-stethoscope',
    color: 'cyan',
    label: 'Evolução Clínica',
  },
  session_performed: {
    icon: 'i-lucide-activity',
    color: 'teal',
    label: 'Sessão Realizada',
  },
  exam_uploaded: {
    icon: 'i-lucide-image',
    color: 'violet',
    label: 'Exame/Imagem',
  },
  document_generated: {
    icon: 'i-lucide-file-text',
    color: 'sky',
    label: 'Documento',
  },
  consent_signed: {
    icon: 'i-lucide-file-signature',
    color: 'purple',
    label: 'Consentimento',
  },
  payment: {
    icon: 'i-lucide-circle-dollar-sign',
    color: 'green',
    label: 'Pagamento',
  },
  refund: { icon: 'i-lucide-receipt', color: 'amber', label: 'Reembolso' },
  status_changed: {
    icon: 'i-lucide-refresh-cw',
    color: 'slate',
    label: 'Status Alterado',
  },
  discharge: { icon: 'i-lucide-log-out', color: 'lime', label: 'Alta Médica' },
  recall_sent: {
    icon: 'i-lucide-bell',
    color: 'yellow',
    label: 'Recall Enviado',
  },
};

// ── Helpers ────────────────────────────────────────────────
const timelineEventConfig = eventType =>
  TIMELINE_TYPE_CONFIG[eventType] ?? {
    icon: 'i-lucide-activity',
    color: 'slate',
    label: eventType,
  };

const tlIconCls = eventType =>
  `tl-icon--${timelineEventConfig(eventType).color}`;
const tlBadgeCls = eventType =>
  `tl-badge--${timelineEventConfig(eventType).color}`;

// ── Computeds ──────────────────────────────────────────────
const filteredTimelineEvents = computed(() => {
  let events =
    timelineFilter.value === 'all'
      ? timelineEvents.value
      : timelineEvents.value.filter(e => {
          if (timelineFilter.value === 'clinical')
            return [
              'clinical_note',
              'anamnesis_filled',
              'session_performed',
            ].includes(e.event_type);
          if (timelineFilter.value === 'appointments')
            return e.event_type.startsWith('appointment');
          if (timelineFilter.value === 'financial')
            return ['payment', 'refund'].includes(e.event_type);
          if (timelineFilter.value === 'documents')
            return [
              'document_generated',
              'consent_signed',
              'exam_uploaded',
            ].includes(e.event_type);
          return true;
        });
  return [...events].sort((a, b) => {
    const da = new Date(a.occurred_at || 0);
    const db = new Date(b.occurred_at || 0);
    return timelineSortOrder.value === 'oldest' ? da - db : db - da;
  });
});

const groupedTimelineEvents = computed(() => {
  const groups = {};
  filteredTimelineEvents.value.forEach(event => {
    const date = event.occurred_at
      ? new Date(event.occurred_at).toLocaleDateString('pt-BR', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          timeZone: BRT,
        })
      : 'Sem data';
    if (!groups[date]) groups[date] = [];
    groups[date].push(event);
  });
  return Object.entries(groups).map(([date, events]) => ({ date, events }));
});

// ── Fetch ──────────────────────────────────────────────────
const fetchTimeline = async () => {
  try {
    timelineLoading.value = true;
    const response = await PatientTimelineAPI.get(route.params.patientId);
    timelineEvents.value = Array.isArray(response.data?.events)
      ? response.data.events
      : [];
  } catch {
    useAlert('Erro ao carregar a timeline do paciente.');
  } finally {
    timelineLoading.value = false;
  }
};

onMounted(() => {
  fetchTimeline();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-6">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Timeline do Paciente
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Visão consolidada de todas as interações, prontuários e
          movimentações.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs text-slate-500">
          {{ filteredTimelineEvents.length }} evento{{
            filteredTimelineEvents.length !== 1 ? 's' : ''
          }}
        </span>
        <!-- Filtro de ordenação -->
        <div class="relative">
          <button
            class="geral-header-btn"
            @click="timelineFilterOpen = !timelineFilterOpen"
          >
            <i class="i-lucide-arrow-up-down w-3.5 h-3.5" />
            {{
              timelineSortOrder === 'oldest' ? 'Mais antigo' : 'Mais recente'
            }}
          </button>
          <div
            v-if="timelineFilterOpen"
            class="tl-sort-dropdown"
            @click.stop
          >
            <button
              v-for="sort in [
                {
                  value: 'newest',
                  label: 'Mais recente primeiro',
                  icon: 'i-lucide-arrow-down-narrow-wide',
                },
                {
                  value: 'oldest',
                  label: 'Mais antigo primeiro',
                  icon: 'i-lucide-arrow-up-narrow-wide',
                },
              ]"
              :key="sort.value"
              class="tl-sort-option"
              :class="{
                'tl-sort-option--active': timelineSortOrder === sort.value,
              }"
              @click="
                timelineSortOrder = sort.value;
                timelineFilterOpen = false;
              "
            >
              <i :class="sort.icon" class="w-3.5 h-3.5" />
              {{ sort.label }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Filtros de categoria (pills) -->
    <div class="tl-filter-row mb-6">
      <button
        v-for="chip in [
          { value: 'all', label: 'Tudo', icon: 'i-lucide-layers' },
          {
            value: 'appointments',
            label: 'Consultas',
            icon: 'i-lucide-calendar',
          },
          {
            value: 'clinical',
            label: 'Clínico',
            icon: 'i-lucide-stethoscope',
          },
          {
            value: 'financial',
            label: 'Financeiro',
            icon: 'i-lucide-circle-dollar-sign',
          },
          {
            value: 'documents',
            label: 'Documentos',
            icon: 'i-lucide-file-text',
          },
        ]"
        :key="chip.value"
        class="tl-filter-btn"
        :class="{ 'tl-filter-btn--active': timelineFilter === chip.value }"
        @click="timelineFilter = chip.value"
      >
        <i :class="chip.icon" class="w-3.5 h-3.5" />
        {{ chip.label }}
      </button>
    </div>

    <!-- Loading -->
    <div
      v-if="timelineLoading"
      class="flex items-center justify-center py-20 gap-3 text-slate-400"
    >
      <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
      <span>Carregando timeline...</span>
    </div>

    <!-- Empty state -->
    <div
      v-else-if="!timelineLoading && filteredTimelineEvents.length === 0"
      class="tl-empty"
    >
      <div class="tl-empty-icon">
        <i class="i-lucide-clock-x w-6 h-6" />
      </div>
      <p class="tl-empty-title">Nenhum evento encontrado</p>
      <p class="tl-empty-hint">
        {{
          timelineFilter !== 'all'
            ? 'Tente remover os filtros aplicados.'
            : 'As interações com o paciente aparecerão aqui.'
        }}
      </p>
      <button
        v-if="timelineFilter !== 'all'"
        class="btn-secondary mt-1"
        @click="timelineFilter = 'all'"
      >
        Limpar filtros
      </button>
    </div>

    <!-- Timeline agrupada por data -->
    <div v-else class="tl-timeline">
      <div
        v-for="group in groupedTimelineEvents"
        :key="group.date"
        class="tl-group"
      >
        <!-- Separador de data -->
        <div class="tl-date-divider">
          <div class="tl-date-line" />
          <span class="tl-date-label">{{ group.date }}</span>
          <div class="tl-date-line" />
        </div>

        <!-- Eventos do grupo -->
        <div class="tl-events">
          <div class="tl-vline" />

          <div
            v-for="event in group.events"
            :key="event.id"
            class="tl-event-row"
          >
            <!-- Ícone circular do evento -->
            <div
              class="tl-event-icon"
              :class="tlIconCls(event.event_type)"
            >
              <i
                :class="timelineEventConfig(event.event_type).icon"
                class="w-4 h-4"
              />
            </div>

            <!-- Card do evento -->
            <div class="tl-event-card">
              <div class="tl-event-header">
                <span
                  class="tl-event-badge"
                  :class="tlBadgeCls(event.event_type)"
                >
                  {{ timelineEventConfig(event.event_type).label }}
                </span>
                <span class="tl-event-time">{{
                  formatTime(event.occurred_at)
                }}</span>
              </div>

              <p class="tl-event-title">{{ event.label }}</p>

              <!-- Metadados -->
              <div
                v-if="
                  event.metadata && Object.keys(event.metadata).length > 0
                "
                class="tl-event-meta"
              >
                <template v-for="(val, key) in event.metadata" :key="key">
                  <div
                    v-if="
                      val && key !== 'account_id' && key !== 'patient_id'
                    "
                    class="tl-meta-item"
                  >
                    <span class="tl-meta-key">{{
                      key.replace(/_/g, ' ')
                    }}</span>
                    <span class="tl-meta-val">{{
                      typeof val === 'string' &&
                      /^\d{4}-\d{2}-\d{2}T/.test(val)
                        ? new Date(val)
                            .toLocaleString('pt-BR', {
                              day: '2-digit',
                              month: '2-digit',
                              year: 'numeric',
                              hour: '2-digit',
                              minute: '2-digit',
                              timeZone: BRT,
                            })
                            .replace(',', ' às')
                        : val
                    }}</span>
                  </div>
                </template>
              </div>

              <!-- Actor -->
              <div v-if="event.actor_name" class="tl-event-actor">
                <i class="i-lucide-user-round w-3 h-3" />
                <span>{{ event.actor_name }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Marcador de início do histórico -->
      <div class="tl-history-end">
        <div class="tl-history-line" />
        <div class="tl-history-dot" />
        <span class="tl-history-label">Início do histórico</span>
        <div class="tl-history-line" />
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ============================================================
   TIMELINE TAB — tl-* design system
   ============================================================ */

/* Filtros de categoria */
.tl-filter-row {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.tl-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 5px 14px;
  border-radius: 99px;
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  background: none;
  border: 1px solid rgba(255, 255, 255, 0.07);
  cursor: pointer;
  transition: background 0.15s, color 0.15s, border-color 0.15s;
}
.tl-filter-btn:hover {
  color: #94a3b8;
  background: rgba(255, 255, 255, 0.04);
}
.tl-filter-btn--active {
  background: rgba(59, 130, 246, 0.12);
  border-color: rgba(59, 130, 246, 0.25);
  color: #60a5fa;
}

/* Dropdown de ordenação */
.tl-sort-dropdown {
  position: absolute;
  right: 0;
  top: calc(100% + 6px);
  z-index: 50;
  background: #0f1118;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 10px;
  padding: 6px;
  min-width: 200px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
}
.tl-sort-option {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 7px;
  font-size: 13px;
  color: #94a3b8;
  background: none;
  border: none;
  cursor: pointer;
  width: 100%;
  text-align: left;
  transition: background 0.12s, color 0.12s;
}
.tl-sort-option:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #e2e8f0;
}
.tl-sort-option--active {
  color: #60a5fa;
  background: rgba(59, 130, 246, 0.1);
}

/* Empty state */
.tl-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 80px 0;
  gap: 12px;
}
.tl-empty-icon {
  width: 56px;
  height: 56px;
  border-radius: 99px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #475569;
}
.tl-empty-title {
  font-size: 15px;
  font-weight: 500;
  color: #94a3b8;
  margin: 0;
}
.tl-empty-hint {
  font-size: 13px;
  color: #475569;
  margin: 0;
  text-align: center;
}

/* Container principal */
.tl-timeline {
  display: flex;
  flex-direction: column;
  gap: 32px;
}
.tl-group {
  display: flex;
  flex-direction: column;
  gap: 0;
}

/* Separador de data */
.tl-date-divider {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 16px;
}
.tl-date-line {
  flex: 1;
  height: 1px;
  background: rgba(255, 255, 255, 0.05);
}
.tl-date-label {
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  white-space: nowrap;
  padding: 3px 12px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 99px;
}

/* Container de eventos do grupo */
.tl-events {
  position: relative;
  padding-left: 44px;
  display: flex;
  flex-direction: column;
  gap: 0;
}
.tl-vline {
  position: absolute;
  left: 19px;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(255, 255, 255, 0.06);
}

.tl-event-row {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 14px;
  padding: 8px 0;
}

.tl-event-icon {
  position: absolute;
  left: -44px;
  top: 12px;
  width: 36px;
  height: 36px;
  border-radius: 99px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  z-index: 2;
}

/* Variantes de ícone semântico */
.tl-icon--indigo { background: #16183a; box-shadow: 0 0 0 1px #4f52a0; color: #a5b4fc; }
.tl-icon--blue { background: #0f1f35; box-shadow: 0 0 0 1px #3b6ea8; color: #93c5fd; }
.tl-icon--orange { background: #1e120a; box-shadow: 0 0 0 1px #8b5a2b; color: #fdba74; }
.tl-icon--yellow { background: #1b1506; box-shadow: 0 0 0 1px #7c6516; color: #fde68a; }
.tl-icon--emerald { background: #0a1f18; box-shadow: 0 0 0 1px #276c52; color: #6ee7b7; }
.tl-icon--red { background: #1e0d0d; box-shadow: 0 0 0 1px #7f2020; color: #fca5a5; }
.tl-icon--rose { background: #1e0d13; box-shadow: 0 0 0 1px #7f2040; color: #fda4af; }
.tl-icon--cyan { background: #0a1e25; box-shadow: 0 0 0 1px #1e6e7e; color: #67e8f9; }
.tl-icon--teal { background: #0a1e1d; box-shadow: 0 0 0 1px #1e6e68; color: #5eead4; }
.tl-icon--violet { background: #140e25; box-shadow: 0 0 0 1px #5837a0; color: #c4b5fd; }
.tl-icon--sky { background: #0b1c2c; box-shadow: 0 0 0 1px #1e5f8c; color: #7dd3fc; }
.tl-icon--purple { background: #180d2a; box-shadow: 0 0 0 1px #6a2e9e; color: #d8b4fe; }
.tl-icon--green { background: #0c1e12; box-shadow: 0 0 0 1px #235c34; color: #86efac; }
.tl-icon--amber { background: #1c1106; box-shadow: 0 0 0 1px #7c4e12; color: #fcd34d; }
.tl-icon--slate { background: #141820; box-shadow: 0 0 0 1px #3a4455; color: #94a3b8; }
.tl-icon--lime { background: #111a06; box-shadow: 0 0 0 1px #4a6a14; color: #bef264; }

/* Card do evento */
.tl-event-card {
  flex: 1;
  background: rgba(255, 255, 255, 0.025);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 12px;
  padding: 14px 16px;
  transition: background 0.15s, border-color 0.15s;
  min-width: 0;
}
.tl-event-card:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.1);
}

.tl-event-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 6px;
}

.tl-event-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.07em;
  text-transform: uppercase;
  padding: 2px 8px;
  border-radius: 5px;
}

.tl-badge--indigo { background: #1e2047; color: #a5b4fc; }
.tl-badge--blue { background: #132440; color: #93c5fd; }
.tl-badge--orange { background: #241508; color: #fdba74; }
.tl-badge--yellow { background: #201a08; color: #fde68a; }
.tl-badge--emerald { background: #0c2219; color: #6ee7b7; }
.tl-badge--red { background: #220f0f; color: #fca5a5; }
.tl-badge--rose { background: #220f16; color: #fda4af; }
.tl-badge--cyan { background: #0c2229; color: #67e8f9; }
.tl-badge--teal { background: #0c2221; color: #5eead4; }
.tl-badge--violet { background: #170f2a; color: #c4b5fd; }
.tl-badge--sky { background: #0d2033; color: #7dd3fc; }
.tl-badge--purple { background: #1b0e2f; color: #d8b4fe; }
.tl-badge--green { background: #0e2215; color: #86efac; }
.tl-badge--amber { background: #211308; color: #fcd34d; }
.tl-badge--slate { background: #171c25; color: #94a3b8; }
.tl-badge--lime { background: #131e07; color: #bef264; }

.tl-event-time {
  font-size: 11px;
  color: #475569;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  flex-shrink: 0;
}

.tl-event-title {
  font-size: 13px;
  font-weight: 500;
  color: #cbd5e1;
  line-height: 1.45;
  margin: 0;
}

.tl-event-meta {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px 24px;
}
.tl-meta-item {
  display: flex;
  align-items: baseline;
  gap: 4px;
  font-size: 12px;
}
.tl-meta-key {
  color: #475569;
  text-transform: capitalize;
  white-space: nowrap;
  flex-shrink: 0;
}
.tl-meta-key::after {
  content: ':';
}
.tl-meta-val {
  color: #94a3b8;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tl-event-actor {
  display: flex;
  align-items: center;
  gap: 5px;
  margin-top: 8px;
  font-size: 11px;
  color: #334155;
}

/* Marcador de início do histórico */
.tl-history-end {
  display: flex;
  align-items: center;
  gap: 10px;
  padding-top: 8px;
}
.tl-history-line {
  flex: 1;
  height: 1px;
  background: rgba(255, 255, 255, 0.04);
}
.tl-history-dot {
  width: 6px;
  height: 6px;
  border-radius: 99px;
  background: #1e293b;
  border: 1px solid rgba(255, 255, 255, 0.1);
  flex-shrink: 0;
}
.tl-history-label {
  font-size: 11px;
  color: #334155;
  white-space: nowrap;
}
</style>
