<script setup>
import { ref, computed, onMounted, onActivated, onBeforeUnmount, getCurrentInstance } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';

// Styles
import '../styles/agenda-events.css';

// Store & Composables
import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';
import { createAgendaState } from '../composables/useAgenda.js';
import { useAgendaInit } from '../composables/useAgendaInit.js';
import { useAgendaCrud } from '../composables/useAgendaCrud.js';
import { useAgendaDnD } from '../composables/useAgendaDnD.js';
import { useAgendaPopups } from '../composables/useAgendaPopups.js';
import { createDefaultNewEvent } from '../utils/agenda-date.js';

// Components
import AgendaSummaryBar from '@plugins/agenda/frontend/features/agenda-summary/AgendaSummaryBar.vue';
import AgendaHeader from '../components/AgendaHeader.vue';
import AgendaSidebar from '../components/AgendaSidebar.vue';
import AgendaMonthView from '../components/AgendaMonthView.vue';
import AgendaTimelineView from '../components/AgendaTimelineView.vue';
import AgendaEventModal from '../components/AgendaEventModal.vue';
import AgendaDeleteModal from '../components/AgendaDeleteModal.vue';
import AgendaEventInfoPopup from '../components/AgendaEventInfoPopup.vue';
import AgendaWlSchedulePopup from '../components/AgendaWlSchedulePopup.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { proxy } = getCurrentInstance();
const t = proxy.$t.bind(proxy);

// Agenda State Setup
const agenda = createAgendaState();
agenda.init();

// Local UI Refs
const newEvent = ref(createDefaultNewEvent());
const wlScheduleEntry = ref(null);
const _returnPatientId = ref(null);

// Component Refs
const timelineArea = ref(null);
const summaryBarRef = ref(null);

// Modules
const { fetchInitialData } = useAgendaInit({ 
  store, 
  agendaState: agenda.state, 
  checkQueryParams: () => checkQueryParams() 
});

const {
  openEventModal,
  closeEventModal,
  openEditEvent,
  saveEvent,
  deleteEvent,
  cancelDelete,
  confirmDelete,
  quickDeleteEvent,
  checkQueryParams
} = useAgendaCrud({ agenda, store, router, route, newEvent, wlScheduleEntry, _returnPatientId });

const {
  initDrag,
  initResize,
  onGlobalMouseMove,
  onGlobalMouseUp
} = useAgendaDnD({ agenda, store, timelineAreaRef: timelineArea });

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

// Lifecycles
onMounted(() => {
  fetchInitialData();
  document.addEventListener('mousemove', onGlobalMouseMove);
  document.addEventListener('mouseup', onGlobalMouseUp);
});

onActivated(() => {
  fetchInitialData();
});

onBeforeUnmount(() => {
  agenda.destroy();
  document.removeEventListener('mousemove', onGlobalMouseMove);
  document.removeEventListener('mouseup', onGlobalMouseUp);
});

// Vuex Getters mapped to computed
const agents = computed(() => store.getters['agents/getAgents']);
const agendaEvents = computed(() => store.getters['agendaEvents/getAgendaEvents']);
const currentUser = computed(() => store.getters['getCurrentUser']);
const contacts = computed(() => store.getters['contacts/getContacts']);

// Proxy agenda Computed Properties for Template
const calendarDays = computed(() => agenda.calendarDays.value);
const calendarWeeks = computed(() => agenda.calendarWeeks.value);
const dayHours = computed(() => agenda.dayHours.value);
const rowHeight = computed(() => agenda.rowHeight.value);
const pixelsPerHour = computed(() => agenda.pixelsPerHour.value);
const currentTimeLineStyle = computed(() => agenda.currentTimeLineStyle.value);
const dragGhostStyle = computed(() => agenda.dragGhostStyle.value);
const isMobile = computed(() => agenda.isMobile.value);

const currentUserID = computed(() => currentUser.value?.id);
const isAdmin = computed(() => {
  const role = currentUser.value?.role;
  return role === 'administrator' || role === 'supervisor';
});

const agentList = computed(() => agenda.buildAgentList(agents.value));
const activeAgents = computed(() => agenda.getActiveAgents(agentList.value, isAdmin.value, currentUserID.value));
const visibleAgentList = computed(() => agenda.getVisibleAgentList(agentList.value, isAdmin.value, currentUserID.value));

const monthLabel = computed(() => agenda.getMonthLabel(t));
const dayHeaders = computed(() => agenda.getDayHeaders(t));
const miniDayHeaders = computed(() => agenda.getMiniDayHeaders(t));
const currentWeekDays = computed(() => agenda.getCurrentWeekDays(t));
const currentDayObj = computed(() => agenda.getCurrentDayObj(t));

const treatmentOptions = computed(() => {
  const services = store.getters['agendaServices/allServices'] || [];
  if (services.length) return services;
  return agenda.state.agendaSettingsData?.treatments || [];
});

const monthEventsMap = computed(() => {
  const map = {};
  if (agenda.state.viewMode !== 'month') return map;
  calendarWeeks.value.forEach(week => {
    week.forEach(dayObj => {
      const events = agenda.getEventsForDay(
        dayObj,
        agendaEvents.value,
        isAdmin.value,
        currentUserID.value,
        treatmentOptions.value
      );
      const key = `${dayObj.year}-${dayObj.month}-${dayObj.day}`;
      map[key] = events.map(e => ({
        ...e,
        _borderColor: agenda.getAgentColor(e, agentList.value, currentUserID.value, treatmentOptions.value),
        _bg: agenda.getEventBackground(e, agentList.value, currentUserID.value, treatmentOptions.value),
      }));
    });
  });
  return map;
});

// Bound Helpers requested by Timeline & Template
const getEventsForDayBound = (dayObj) => agenda.getEventsForDay(dayObj, agendaEvents.value, isAdmin.value, currentUserID.value, treatmentOptions.value);
const calculateOverlapsBound = (events) => agenda.calculateOverlaps(events);
const getEventBackgroundBound = (event) => agenda.getEventBackground(event, agentList.value, currentUserID.value, treatmentOptions.value);
const getAgentColorBound = (event) => agenda.getAgentColor(event, agentList.value, currentUserID.value, treatmentOptions.value);
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
  openEventModal({ dayObj, hourStr: hour, agent });
};

// Expose internal navigation to template
const prevPeriod = () => agenda.prevPeriod();
const nextPeriod = () => agenda.nextPeriod();
const goToToday = () => agenda.goToToday();
const setViewMode = (mode) => agenda.setViewMode(mode);
const handleMiniCalendarClick = (dayObj) => agenda.handleMiniCalendarClick(dayObj);
const toggleFilter = (key) => agenda.toggleFilter(key);
const toggleAgent = (id) => agenda.toggleAgent(id);
const togglePriority = (val) => agenda.togglePriority(val);
const toggleEventType = (val) => agenda.toggleEventType(val);
const toggleTreatment = (val) => agenda.toggleTreatment(val);
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
      @new-event="openEventModal()"
      @refresh-summary="$refs.summaryBarRef.refresh()"
      @update:view-dropdown-open="v => (agenda.state.viewDropdownOpen = v)"
    />

    <!-- MOBILE FAB -->
    <button class="mobile-fab" @click="openEventModal()">
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
    <div class="agenda-body">
      <!-- MONTH VIEW -->
      <AgendaMonthView
        v-if="agenda.state.viewMode === 'month'"
        :calendar-weeks="calendarWeeks"
        :day-headers="dayHeaders"
        :events-map="monthEventsMap"
        :get-day-block-info="getDayBlockInfoBound"
        :is-day-blocked="isDayBlockedBound"
        :is-day-in-past="isDayInPastBound"
        @click-day="openEventModal({ dayObj: $event })"
        @click-event="toggleEventInfo($event)"
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
        :agenda-events="agendaEvents"
        :agent-list="agentList"
        :current-user-i-d="currentUserID"
        :is-admin="isAdmin"
        :current-time-line-style="currentTimeLineStyle"
        :is-dragging="agenda.state.isDragging"
        :dragging-event="agenda.state.draggingEvent"
        :dragging-event-id="agenda.state.draggingEventId"
        :drag-current-day-obj="agenda.state.dragCurrentDayObj"
        :drag-current-starts-at="agenda.state.dragCurrentStartsAt"
        :drag-current-ends-at="agenda.state.dragCurrentEndsAt"
        :drag-ghost-style="dragGhostStyle"
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
        :is-admin="isAdmin"
        :visible-agent-list="visibleAgentList"
        :hidden-agents="agenda.state.hiddenAgents"
        :hidden-priorities="agenda.state.hiddenPriorities"
        :hidden-event-types="agenda.state.hiddenEventTypes"
        :hidden-treatments="agenda.state.hiddenTreatments"
        :expanded-filters="agenda.state.expandedFilters"
        :treatment-options="treatmentOptions"
        :waiting-list-entries="waitingListStore.entries"
        :wl-info-popup="agenda.state.wlInfoPopup"
        :show-mobile-sidebar="agenda.state.showMobileSidebar"
        @mini-click="handleMiniCalendarClick"
        @toggle-filter="toggleFilter"
        @toggle-agent="toggleAgent"
        @toggle-priority="togglePriority"
        @toggle-event-type="toggleEventType"
        @toggle-treatment="toggleTreatment"
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

    <!-- EVENT MODAL -->
    <AgendaEventModal
      :show="agenda.state.showNewEventModal"
      :is-editing="agenda.state.isEditing"
      :editing-event-id="agenda.state.editingEventId"
      :new-event="newEvent"
      :custom-attributes-config="agenda.state.customAttributesConfig"
      :agents="visibleAgentList"
      :treatment-options="treatmentOptions"
      :is-saving="agenda.state.isSaving"
      :is-deleting="agenda.state.isDeleting"
      @close="closeEventModal"
      @save="saveEvent"
      @delete="deleteEvent"
      @update:new-event="v => (newEvent = v)"
    />

    <!-- DELETE MODAL -->
    <AgendaDeleteModal
      :show="agenda.state.showConfirmDelete"
      :is-deleting="agenda.state.isDeleting"
      @cancel="cancelDelete"
      @confirm="confirmDelete"
    />

    <!-- EVENT INFO POPUP -->
    <AgendaEventInfoPopup
      v-if="agenda.state.eventInfoPopup && getInfoPopupEvent()"
      :event="getInfoPopupEvent()"
      :position="agenda.state.eventInfoPopup"
      :agents="agentList"
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
