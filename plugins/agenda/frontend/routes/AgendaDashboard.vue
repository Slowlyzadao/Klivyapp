<script setup>
import { ref, computed, onMounted, onActivated, onBeforeUnmount, getCurrentInstance } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';

// Styles
import '@plugins/agenda/frontend/styles/agenda-events.scss';

// Store & Composables
import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';
import { useAgendaEventLauncher } from '../composables/useAgendaEventLauncher.js';
import { useAgendaDnD } from '../composables/useAgendaDnD.js';
import { useAgendaPopups } from '../composables/useAgendaPopups.js';
import { parseEventDate } from '../utils/agenda-date.js';
import { STATUS_OPTIONS } from '../utils/agenda-constants.js';
import { usePermissions } from 'dashboard/composables/usePermissions';

const STATUS_OPTIONS_KEYS = STATUS_OPTIONS.map(o => o.key);

// Components — AgendaEventModal e AgendaDeleteModal são montados pelo
// AgendaEventLauncherOutlet em Dashboard.vue (overlay global compartilhado
// com o botão "Agendar consulta" em ContactInfo.vue).
import AgendaSummaryBar from '@plugins/agenda/frontend/features/agenda-summary/AgendaSummaryBar.vue';
import AgendaHeader from '../components/AgendaHeader.vue';
import AgendaSidebar from '../components/AgendaSidebar.vue';
import AgendaMonthView from '../components/AgendaMonthView.vue';
import AgendaTimelineView from '../components/AgendaTimelineView.vue';
import AgendaYearView from '../components/AgendaYearView.vue';
import AgendaEventInfoPopup from '../components/AgendaEventInfoPopup.vue';
import AgendaWlSchedulePopup from '../components/AgendaWlSchedulePopup.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { proxy } = getCurrentInstance();
const t = proxy.$t.bind(proxy);

// Agenda State — singleton compartilhado com o outlet em Dashboard.vue e o
// botão "Agendar consulta" em ContactInfo.vue. O launcher cuida da carga
// inicial (agentes, settings, custom attrs, eventos) na primeira chamada
// a `ensureLoaded()` ou `open()` — idempotente em chamadas seguintes.
const launcher = useAgendaEventLauncher();
const agenda = launcher.agenda;
const newEvent = launcher.newEvent;
const wlScheduleEntry = launcher.wlScheduleEntry;

// Component Refs
const timelineArea = ref(null);
const summaryBarRef = ref(null);

// Handlers vindos do launcher — `openEventModal` aqui aponta para
// `launcher.open`, que aceita o mesmo payload do antigo `openEventModal`
// (dayObj/hourStr/agent) e ainda suporta pré-preenchimento de paciente
// quando chamado a partir de Conversas. Os handlers do modal em si
// (close/save/delete/cancelDelete/confirmDelete) são consumidos pelo
// AgendaEventLauncherOutlet em Dashboard.vue, não aqui.
const openEventModal = launcher.open;
const openEditEvent = launcher.openEditEvent;
const quickDeleteEvent = launcher.quickDeleteEvent;
const checkQueryParams = launcher.checkQueryParams;

const {
  toggleEventInfo,
  closeEventInfoPopup,
  getInfoPopupEvent,
  updateEventStatus,
  openPatientRecord,
  openWlScheduleForCell,
  closeWlScheduleModal,
  confirmWlSchedule,
  showWlInfo,
  closeWlInfo
} = useAgendaPopups({ agenda, agendaEvents: computed(() => store.getters['agendaEvents/getAgendaEvents']), router, route, store, newEvent, wlScheduleEntry, openEventModal });

// Vuex Getters mapped to computed
const agents = computed(() => store.getters['agents/getAgents']);
const agendaEvents = computed(() => store.getters['agendaEvents/getAgendaEvents']);
const currentUser = computed(() => store.getters['getCurrentUser']);
const eventsUiFlags = computed(() => store.getters['agendaEvents/getUIFlags'] || {});
const isFetchingEvents = computed(() => !!eventsUiFlags.value.isFetching);

// Proxy agenda Computed Properties for Template
const calendarDays = computed(() => agenda.calendarDays.value);
const calendarWeeks = computed(() => agenda.calendarWeeks.value);
const dayHours = computed(() => agenda.dayHours.value);
const rowHeight = computed(() => agenda.rowHeight.value);
const pixelsPerHour = computed(() => agenda.pixelsPerHour.value);
const slotIntervalMinutes = computed(
  () => agenda.agendaSettings.value?.slot_interval_minutes || 60,
);
const visibleStartHour = computed(() => agenda.visibleStartHour.value);
const currentTimeLineStyle = computed(() => agenda.currentTimeLineStyle.value);
const dragGhostStyle = computed(() => agenda.dragGhostStyle.value);
const isMobile = computed(() => agenda.isMobile.value);

const currentUserID = computed(() => currentUser.value?.id);
const { can: klivyCan, scope: klivyScope } = usePermissions();

const isAdmin = computed(() => {
  const role = currentUser.value?.role;
  return role === 'administrator' || role === 'supervisor';
});

// Quem pode ver TODAS as colunas da agenda (não apenas a própria):
//   - Administrador Chatwoot (bypass)
//   - Usuário com KlivyRole tendo `agenda.view` + scope='all'
// Especialista comum (provider) com scope='own' continua vendo apenas
// sua própria coluna. Gerente/Recepcionista (não-providers, com view) veem
// o calendário inteiro pra coordenar.
const canViewAllAgenda = computed(() => {
  if (isAdmin.value) return true;
  return klivyCan('agenda', 'view') && klivyScope('agenda') === 'all';
});

const agentList = computed(() => agenda.buildAgentList(agents.value));
const activeAgents = computed(() => agenda.getActiveAgents(agentList.value, canViewAllAgenda.value, currentUserID.value));
const visibleAgentList = computed(() => agenda.getVisibleAgentList(agentList.value, canViewAllAgenda.value, currentUserID.value));

const monthLabel = computed(() => agenda.getMonthLabel(t));
const currentDateLabel = computed(() => agenda.getCurrentDateLabel(t));
const dayHeaders = computed(() => agenda.getDayHeaders(t));
const miniDayHeaders = computed(() => agenda.getMiniDayHeaders(t));
const currentWeekDays = computed(() => agenda.getCurrentWeekDays(t));
const currentDayObj = computed(() => agenda.getCurrentDayObj(t));

// DnD must be initialized after currentWeekDays/activeAgents are declared
// (they are passed as reactive refs and the composable reads them at runtime)
const {
  initDrag,
  initResize,
  onGlobalMouseMove,
  onGlobalMouseUp
} = useAgendaDnD({
  agenda,
  store,
  timelineAreaRef: timelineArea,
  currentWeekDays,
  activeAgents,
  onBlockedDrop: (reason) => {
    const label = typeof reason === 'string' ? reason : 'Horário indisponível';
    useAlert(`Não é possível mover o evento para este horário (${label}).`);
  },
});

// Lifecycles
// `ensureLoaded()` é idempotente — primeira chamada faz o carregamento
// pesado (settings, custom attrs, agentes, services, categories, eventos);
// chamadas seguintes (onActivated com KeepAlive ou abertura via Conversas)
// só refazem fetch da janela visível. NÃO chamamos `agenda.destroy()` ao
// desmontar: o agenda state é singleton e precisa sobreviver entre rotas
// para que o modal possa ser aberto a partir de Conversas.
onMounted(() => {
  launcher.ensureLoaded();
  checkQueryParams();
  document.addEventListener('mousemove', onGlobalMouseMove);
  document.addEventListener('mouseup', onGlobalMouseUp);
});

onActivated(() => {
  launcher.ensureLoaded();
});

onBeforeUnmount(() => {
  document.removeEventListener('mousemove', onGlobalMouseMove);
  document.removeEventListener('mouseup', onGlobalMouseUp);
});

const treatmentOptions = computed(() => {
  const services = store.getters['agendaServices/allServices'] || [];
  if (services.length) return services;
  return agenda.state.agendaSettingsData?.treatments || [];
});

const categoryOptions = computed(() => {
  return store.getters['agendaCategories/activeCategories'] || [];
});

const eventTypeCounts = computed(() => {
  const counts = {};
  for (const e of agendaEvents.value || []) {
    const key = e.event_type || 'consultation';
    counts[key] = (counts[key] || 0) + 1;
  }
  return counts;
});

// Auditoria 2026-05-15: badge de contagem por status no sidebar.
// Espelha eventTypeCounts. Agrupa pelos 7 status do enum AgendaEvent.
// `cancelled` deixou de ser invisível depois da reconciliação Clinicorp.
const statusCounts = computed(() => {
  const counts = {};
  for (const e of agendaEvents.value || []) {
    const key = e.status || 'scheduled';
    counts[key] = (counts[key] || 0) + 1;
  }
  return counts;
});

// Filtra + agrupa todos os eventos por chave-do-dia em um único pass O(n).
// Antes: getEventsForDay percorria os 8k eventos uma vez por dia da grade
// (8k × 7 dias = 56k iterações por render). Agora: 8k × 1 = 8k, e a consulta
// por dia vira O(1) via Map.get. Recomputa só quando a lista de eventos ou os
// filtros (agentes/prioridades/tipos/tratamentos ocultos) mudam.
const eventsByDayKey = computed(() => {
  const events = agendaEvents.value || [];
  const canViewAll = canViewAllAgenda.value;
  const uid = currentUserID.value;
  const { hiddenAgents, hiddenPriorities, hiddenEventTypes, hiddenServiceIds, hiddenStatuses } = agenda.state;
  const map = new Map();

  // Lookup auxiliar para o fallback de NAME nos eventos legados (agenda_service_id NULL).
  const treatmentByName = new Map();
  for (const t of treatmentOptions.value || []) {
    if (t?.name) treatmentByName.set(t.name, t.id);
  }

  const { hiddenCategories } = agenda.state;
  for (const e of events) {
    if (!canViewAll && e.user_id !== uid) continue;
    if (hiddenAgents.includes(e.user_id)) continue;
    const prio = e.custom_attributes?.priority || 'medium';
    if (hiddenPriorities.includes(prio)) continue;
    const evType = e.event_type || 'consultation';
    if (hiddenEventTypes.includes(evType)) continue;
    // PR #6 da auditoria 2026-05-13: filtro por ID (estável a rename). Fallback
    // por NAME só para eventos com agenda_service_id NULL (legados pré-PR #5).
    if (e.agenda_service_id != null) {
      if (hiddenServiceIds.includes(e.agenda_service_id)) continue;
    } else {
      const treatment = e.custom_attributes?.treatment;
      if (treatment) {
        const sid = treatmentByName.get(treatment);
        if (sid != null && hiddenServiceIds.includes(sid)) continue;
      }
    }
    if (e.category_id && hiddenCategories.includes(e.category_id)) continue;
    // Filtro de status só vale pra Consulta (único tipo com fluxo de
    // atendimento). Compromisso/Bloqueio passam direto.
    if (
      evType === 'consultation' &&
      hiddenStatuses.includes(e.status || 'scheduled')
    )
      continue;

    const d = parseEventDate(e.starts_at || e.start_time);
    const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    let bucket = map.get(key);
    if (!bucket) {
      bucket = [];
      map.set(key, bucket);
    }
    bucket.push(e);
  }

  // Sort cada bucket uma vez — antes era um sort por chamada de getEventsForDay.
  for (const bucket of map.values()) {
    bucket.sort(
      (a, b) =>
        parseEventDate(a.starts_at || a.start_time) -
        parseEventDate(b.starts_at || b.start_time)
    );
  }
  return map;
});

const getEventsForDayBound = (dayObj) => {
  const key = `${dayObj.year}-${dayObj.month}-${dayObj.day}`;
  return eventsByDayKey.value.get(key) || [];
};

const monthEventsMap = computed(() => {
  const map = {};
  if (agenda.state.viewMode !== 'month') return map;
  calendarWeeks.value.forEach(week => {
    week.forEach(dayObj => {
      const events = getEventsForDayBound(dayObj);
      const key = `${dayObj.year}-${dayObj.month}-${dayObj.day}`;
      map[key] = events.map(e => ({
        ...e,
        _borderColor: agenda.getAgentColor(e, agentList.value, currentUserID.value, treatmentOptions.value, categoryOptions.value),
        _bg: agenda.getEventBackground(e, agentList.value, currentUserID.value, treatmentOptions.value, categoryOptions.value),
      }));
    });
  });
  return map;
});
const calculateOverlapsBound = (events) => agenda.calculateOverlaps(events);
const getEventBackgroundBound = (event) => agenda.getEventBackground(event, agentList.value, currentUserID.value, treatmentOptions.value, categoryOptions.value);
const getAgentColorBound = (event) => agenda.getAgentColor(event, agentList.value, currentUserID.value, treatmentOptions.value, categoryOptions.value);
const getTreatmentColorBound = (event) => agenda.getTreatmentColor(event, treatmentOptions.value);
const getCategoryColorBound = (event) => agenda.getCategoryColor(event, categoryOptions.value);
const getStatusConfigBound = (status) => agenda.getStatusConfig(status);
const isEventLateBound = (event) => agenda.isEventLate(event);
const isHourBlockedBound = (dayObj, hour) => agenda.isHourBlocked(dayObj, hour);
const getWlMatchBound = (dayObj, hour) => agenda.getWaitingListMatchForCell(dayObj, hour, waitingListStore.entries);
const getDayBlockInfoBound = (dayObj) => agenda.getDayBlockInfo(dayObj);
const isDayBlockedBound = (dayObj) => agenda.isDayBlocked(dayObj);
const isDayInPastBound = (dayObj) => agenda.isDayInPast(dayObj);

const handleCellClick = ({ dayObj, hour, agent }) => {
  if (agenda.isHourBlocked(dayObj, hour)) {
    agenda.getBlockedMessage(dayObj, hour, useAlert);
    return;
  }
  // Week view doesn't pass an agent. When a single agent is currently visible
  // (solo or all-but-one hidden), default to that agent so the modal opens preselected.
  const resolvedAgent = agent || (activeAgents.value.length === 1 ? activeAgents.value[0] : null);
  openEventModal({ dayObj, hourStr: hour, agent: resolvedAgent });
};

// "+N mais" no mês → entra no Day view daquele dia em vez de abrir o
// modal de novo evento (que era o comportamento errado quando o clique
// borbulhava para o cell). Day view mostra a lista completa naturalmente.
const handleViewDay = (dayObj) => {
  agenda.handleMiniCalendarClick(dayObj);
  agenda.setViewMode('day');
};

// Clique no nome do mês na Year View → abre Month View daquele mês.
// dayObj traz { year, month } (month 0-indexado, como o resto do calendário).
const handleViewMonth = ({ year, month }) => {
  agenda.handleMiniCalendarClick({ year, month, day: 1 });
  agenda.setViewMode('month');
};

// Expose internal navigation to template
const prevPeriod = () => agenda.prevPeriod();
const nextPeriod = () => agenda.nextPeriod();
const goToToday = () => agenda.goToToday();
const setViewMode = (mode) => agenda.setViewMode(mode);
const handleMiniCalendarClick = (dayObj) => agenda.handleMiniCalendarClick(dayObj);
const toggleFilter = (key) => agenda.toggleFilter(key);
const toggleAgent = (id) => agenda.toggleAgent(id);
const soloAgent = (id) => agenda.soloAgent(id, agentList.value.map(a => a.id));
const showAllAgents = () => agenda.showAllAgents();

const openNewEvent = (opts = {}) => {
  const preselected = activeAgents.value.length === 1 ? activeAgents.value[0] : null;
  openEventModal({ ...opts, agent: opts.agent || preselected });
};
const togglePriority = (val) => agenda.togglePriority(val);
const toggleEventType = (val) => agenda.toggleEventType(val);
const toggleTreatment = (val) => agenda.toggleTreatment(val);
const toggleCategory = (id) => agenda.toggleCategory(id);
const soloCategory = (id) => agenda.soloCategory(id, categoryOptions.value.map(c => c.id));
const showAllCategories = () => agenda.showAllCategories();
const toggleStatus = (val) => agenda.toggleStatus(val);
const soloStatus = (val) => agenda.soloStatus(val, STATUS_OPTIONS_KEYS);
const showAllStatuses = () => agenda.showAllStatuses();
</script>

<template>
  <div ref="agendaRoot" class="agenda-container">
    <!-- HEADER -->
    <AgendaHeader
      :month-label="monthLabel"
      :view-mode="agenda.state.viewMode"
      :show-summary-bar="agenda.state.showSummaryBar"
      :show-mobile-sidebar="agenda.state.showMobileSidebar"
      :view-dropdown-open="agenda.state.viewDropdownOpen"
      @prev="prevPeriod"
      @next="nextPeriod"
      @today="goToToday"
      @set-view-mode="setViewMode"
      @toggle-summary="agenda.state.showSummaryBar = !agenda.state.showSummaryBar"
      @toggle-sidebar="agenda.state.showMobileSidebar = !agenda.state.showMobileSidebar"
      @new-event="openNewEvent()"
      @refresh-summary="$refs.summaryBarRef.refresh()"
      @update:view-dropdown-open="v => (agenda.state.viewDropdownOpen = v)"
    />

    <!-- MOBILE FAB -->
    <button class="mobile-fab" @click="openNewEvent()">
      <i class="i-lucide-plus" />
    </button>

    <!-- SUMMARY BAR -->
    <div class="agsum-bar" :class="{ 'agsum-bar--open': agenda.state.showSummaryBar }">
      <AgendaSummaryBar
        ref="summaryBarRef"
        :view-mode="agenda.state.viewMode"
        :current-date="agenda.state.currentDate"
        :current-week-days="currentWeekDays"
      />
    </div>

    <!-- BODY -->
    <div class="agenda-body relative">
      <!-- Loading bar: aparece durante refetch de eventos (Fase 4 UX). -->
      <!-- Não substitui a grade: eventos do cache continuam visíveis enquanto -->
      <!-- a request roda — a barra é só um sinal sutil para o usuário. -->
      <div
        v-if="isFetchingEvents"
        class="absolute top-0 left-0 right-0 h-0.5 z-50 bg-blue-500 animate-loader-pulse pointer-events-none"
        aria-hidden="true"
      />
      <!-- YEAR VIEW -->
      <AgendaYearView
        v-if="agenda.state.viewMode === 'year'"
        :current-date="agenda.state.currentDate"
        :hidden-statuses="agenda.state.hiddenStatuses"
        :is-dark-theme="agenda.state.isDarkTheme"
        :is-day-blocked="isDayBlockedBound"
        :get-day-block-info="getDayBlockInfoBound"
        @view-day="handleViewDay"
        @view-month="handleViewMonth"
      />

      <!-- MONTH VIEW -->
      <AgendaMonthView
        v-else-if="agenda.state.viewMode === 'month'"
        :calendar-weeks="calendarWeeks"
        :day-headers="dayHeaders"
        :events-map="monthEventsMap"
        :get-day-block-info="getDayBlockInfoBound"
        :is-day-blocked="isDayBlockedBound"
        :is-day-in-past="isDayInPastBound"
        @click-day="openNewEvent({ dayObj: $event })"
        @click-event="toggleEventInfo($event)"
        @view-day="handleViewDay"
      />

      <!-- TIMELINE VIEW (WEEK/DAY) -->
      <AgendaTimelineView
        v-else
        ref="timelineArea"
        :view-mode="agenda.state.viewMode"
        :layout-mode="agenda.state.layoutMode"
        :active-agents="activeAgents"
        :current-week-days="currentWeekDays"
        :current-day-obj="currentDayObj"
        :day-hours="dayHours"
        :row-height="rowHeight"
        :pixels-per-hour="pixelsPerHour"
        :slot-interval-minutes="slotIntervalMinutes"
        :visible-start-hour="visibleStartHour"
        :agenda-events="agendaEvents"
        :agent-list="agentList"
        :current-user-i-d="currentUserID"
        :is-admin="canViewAllAgenda"
        :current-time-line-style="currentTimeLineStyle"
        :is-dragging="agenda.state.isDragging"
        :dragging-event="agenda.state.draggingEvent"
        :dragging-event-id="agenda.state.draggingEventId"
        :drag-current-day-obj="agenda.state.dragCurrentDayObj"
        :drag-current-starts-at="agenda.state.dragCurrentStartsAt"
        :drag-current-ends-at="agenda.state.dragCurrentEndsAt"
        :drag-ghost-style="dragGhostStyle"
        :drag-is-blocked="agenda.state.dragIsBlocked"
        :drag-block-reason="agenda.state.dragBlockReason"
        :is-resizing="agenda.state.isResizing"
        :resizing-event-id="agenda.state.resizingEventId"
        :resizing-event-end-at="agenda.state.resizingEventEndAt"
        :is-hour-blocked="isHourBlockedBound"
        :get-day-block-info="getDayBlockInfoBound"
        :get-waiting-list-match-for-cell="getWlMatchBound"
        :get-events-for-day="getEventsForDayBound"
        :calculate-overlaps="calculateOverlapsBound"
        :get-event-background="getEventBackgroundBound"
        :get-agent-color="getAgentColorBound"
        :get-treatment-color="getTreatmentColorBound"
        :get-category-color="getCategoryColorBound"
        :get-status-config="getStatusConfigBound"
        :is-event-late="isEventLateBound"
        :is-dark-theme="agenda.state.isDarkTheme"
        @click-cell="handleCellClick"
        @click-event="toggleEventInfo($event)"
        @init-drag="initDrag($event)"
        @init-resize="initResize($event)"
        @wl-cell-click="openWlScheduleForCell($event)"
        @quick-delete="quickDeleteEvent($event)"
      />

      <!-- SIDEBAR -->
      <AgendaSidebar
        :calendar-days="calendarDays"
        :mini-day-headers="miniDayHeaders"
        :current-date-label="currentDateLabel"
        :is-admin="canViewAllAgenda"
        :visible-agent-list="visibleAgentList"
        :hidden-agents="agenda.state.hiddenAgents"
        :hidden-priorities="agenda.state.hiddenPriorities"
        :hidden-event-types="agenda.state.hiddenEventTypes"
        :hidden-service-ids="agenda.state.hiddenServiceIds"
        :hidden-categories="agenda.state.hiddenCategories"
        :hidden-statuses="agenda.state.hiddenStatuses"
        :expanded-filters="agenda.state.expandedFilters"
        :treatment-options="treatmentOptions"
        :category-options="categoryOptions"
        :event-type-counts="eventTypeCounts"
        :status-counts="statusCounts"
        :waiting-list-entries="waitingListStore.entries"
        :wl-info-popup="agenda.state.wlInfoPopup"
        :show-mobile-sidebar="agenda.state.showMobileSidebar"
        @mini-click="handleMiniCalendarClick"
        @toggle-filter="toggleFilter"
        @toggle-agent="toggleAgent"
        @solo-agent="soloAgent"
        @show-all-agents="showAllAgents"
        @toggle-priority="togglePriority"
        @toggle-event-type="toggleEventType"
        @toggle-treatment="toggleTreatment"
        @toggle-category="toggleCategory"
        @solo-category="soloCategory"
        @show-all-categories="showAllCategories"
        @toggle-status="toggleStatus"
        @solo-status="soloStatus"
        @show-all-statuses="showAllStatuses"
        @show-wl-info="showWlInfo"
        @close-wl-info="closeWlInfo"
        @remove-wl="id => waitingListStore.remove(id)"
        @close-mobile="agenda.state.showMobileSidebar = false"
      />
    </div>

    <!-- WL SCHEDULE POPUP -->
    <AgendaWlSchedulePopup
      :show="agenda.state.showWlScheduleModal"
      :cell-popup="agenda.state.wlCellPopup"
      @close="closeWlScheduleModal"
      @select="confirmWlSchedule"
    />

    <!--
      AgendaEventModal e AgendaDeleteModal são montados pelo
      AgendaEventLauncherOutlet em Dashboard.vue (overlay global).
      Manter uma única instância evita duplicar o Teleport no body
      quando o modal é aberto a partir de Conversas.
    -->

    <!-- EVENT INFO POPUP -->
    <AgendaEventInfoPopup
      v-if="agenda.state.eventInfoPopup && getInfoPopupEvent()"
      :event="getInfoPopupEvent()"
      :position="agenda.state.eventInfoPopup"
      :agents="agentList"
      :treatment-options="treatmentOptions"
      :custom-attributes-config="agenda.state.customAttributesConfig"
      :status-updating-id="agenda.state.statusUpdatingId"
      @close="closeEventInfoPopup"
      @edit="openEditEvent"
      @status-change="updateEventStatus"
      @open-patient="openPatientRecord"
    />
  </div>
</template>

<style scoped>
.agenda-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  overflow: hidden;
  background: rgb(var(--surface-1));
  max-width: 100% !important;
  overflow-x: hidden !important;
}

.agenda-body {
  display: flex;
  flex: 1;
  overflow: hidden;
  min-width: 0 !important;
  min-height: 0 !important;
  overflow-x: hidden !important;
}

.agsum-bar {
  max-height: 0;
  overflow: hidden;
  transition: max-height 0.3s ease;
}

.agsum-bar--open {
  max-height: 500px;
}

/* Mobile FAB */
.mobile-fab {
  position: fixed;
  bottom: 24px;
  right: 24px;
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: none;
  background: rgb(var(--blue-9));
  color: #fff;
  display: none;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 98;
  box-shadow:
    0 4px 16px rgba(59, 130, 246, 0.35),
    0 2px 8px rgba(0, 0, 0, 0.15);
  transition: all 0.2s;
}

.mobile-fab:hover {
  transform: translateY(-2px) scale(1.05);
  box-shadow:
    0 8px 24px rgba(59, 130, 246, 0.4),
    0 4px 12px rgba(0, 0, 0, 0.2);
}

.mobile-fab:active {
  transform: scale(0.95);
}

.mobile-fab i {
  width: 24px;
  height: 24px;
}

@media (max-width: 767px) {
  .agenda-body {
    flex-direction: column;
  }

  .mobile-fab {
    display: flex;
  }
}
</style>

<!-- Unscoped: prevent horizontal scroll -->
<style>
html:has(.agenda-container),
body:has(.agenda-container) {
  overflow-x: hidden !important;
}

/* Light mode: modal overrides */
body:not(.dark) .agenda-new-event-modal {
  background: rgb(var(--slate-1)) !important;
  border-color: rgb(var(--slate-4)) !important;
  color: rgb(var(--slate-12)) !important;
}

body:not(.dark) .agenda-new-event-modal input,
body:not(.dark) .agenda-new-event-modal select,
body:not(.dark) .agenda-new-event-modal textarea {
  background: rgb(var(--slate-2)) !important;
  border-color: rgb(var(--slate-5)) !important;
  color: rgb(var(--slate-12)) !important;
}

/* Mobile responsive modal */
@media (max-width: 767px) {
  .modal-overlay-responsive {
    align-items: flex-end !important;
    padding: 0 !important;
  }

  .modal-wrapper-responsive {
    flex-direction: column !important;
    width: 100% !important;
    max-height: 92vh !important;
    animation: slideUp 0.3s cubic-bezier(0.16, 1, 0.3, 1) !important;
  }

  @keyframes slideUp {
    from { transform: translateY(100%); opacity: 0.8; }
    to   { transform: translateY(0);    opacity: 1; }
  }

  .modal-wrapper-responsive .agenda-new-event-modal {
    width: 100% !important;
    max-width: 100% !important;
    max-height: 92vh !important;
    border-radius: 20px 20px 0 0 !important;
    margin: 0 !important;
    overflow-y: auto !important;
  }

  .modal-wrapper-responsive > div:nth-child(2) {
    width: 100% !important;
    border-top: 1px solid rgb(var(--slate-4)) !important;
    border-radius: 0 !important;
    max-height: 50vh !important;
    overflow-y: auto !important;
  }

  .modal-wrapper-responsive .agenda-new-event-modal::before {
    content: '';
    display: block;
    width: 36px;
    height: 4px;
    background: rgb(var(--slate-6));
    border-radius: 4px;
    margin: 8px auto 4px;
    flex-shrink: 0;
  }

  .form-row-2,
  .form-row-3,
  .grid.grid-cols-2 {
    grid-template-columns: 1fr !important;
    gap: 10px !important;
  }

  .evt-info-popup {
    /* Unificado via componente AgendaEventInfoPopup.vue */
  }
}
</style>
