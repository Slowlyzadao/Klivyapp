<script>
import { PRIORITIES, EVENT_TYPES, TREATMENTS, PERIOD_LABELS, DOW_LABELS_PT } from '../utils/agenda-constants.js';
import { getPriorityColor } from '../utils/agenda-colors.js';

export default {
  name: 'AgendaSidebar',
  props: {
    calendarDays: { type: Array, required: true },
    miniDayHeaders: { type: Array, required: true },
    isAdmin: { type: Boolean, default: false },
    visibleAgentList: { type: Array, default: () => [] },
    hiddenAgents: { type: Array, default: () => [] },
    hiddenPriorities: { type: Array, default: () => [] },
    hiddenEventTypes: { type: Array, default: () => [] },
    hiddenTreatments: { type: Array, default: () => [] },
    expandedFilters: { type: Object, required: true },
    treatmentOptions: { type: Array, default: () => TREATMENTS },
    waitingListEntries: { type: Array, default: () => [] },
    wlInfoPopup: { type: Object, default: null },
    showMobileSidebar: { type: Boolean, default: false },
  },
  emits: [
    'mini-click',
    'toggle-filter',
    'toggle-agent',
    'toggle-priority',
    'toggle-event-type',
    'toggle-treatment',
    'show-wl-info',
    'close-wl-info',
    'remove-wl',
    'close-mobile',
  ],
  data() {
    return {
      priorityOptions: PRIORITIES,
      eventTypeOptions: EVENT_TYPES,
    };
  },
  methods: {
    getPriorityColor,
    isToday(dayObj) {
      const n = new Date();
      return (
        dayObj.day === n.getDate() &&
        dayObj.month === n.getMonth() &&
        dayObj.year === n.getFullYear()
      );
    },
    isSelectedDate(dayObj) {
      // Delegated via prop or simple today-check
      return false;
    },
    getPeriodLabel(period) {
      return PERIOD_LABELS[period] || period;
    },
    getDowLabel(d) {
      return DOW_LABELS_PT[d] || d;
    },
  },
};
</script>

<template>

    <!-- Mobile overlay -->
    <div
      v-if="showMobileSidebar"
      class="mobile-sidebar-overlay"
      @click="$emit('close-mobile')"
    />

    <div
      class="agenda-sidebar"
      :class="{ 'mobile-open': showMobileSidebar }"
    >
      <!-- Mini Calendar -->
      <div class="sidebar-section">
        <div class="sidebar-title">
          {{ $t('AGENDA.SIDEBAR.MINI_CALENDAR') }}
        </div>
        <div class="mini-calendar">
          <div class="mini-cal-header">
            <span
              v-for="(d, index) in miniDayHeaders"
              :key="index"
              class="mini-day-label"
            >{{ d }}</span>
          </div>
          <div class="mini-cal-grid">
            <span
              v-for="(dayObj, idx) in calendarDays.slice(0, 42)"
              :key="idx"
              class="mini-day"
              :class="{
                'other-month': !dayObj.isCurrentMonth,
                today: isToday(dayObj),
              }"
              @click="$emit('mini-click', dayObj)"
            >
              {{ dayObj.day }}
            </span>
          </div>
        </div>
      </div>

      <!-- Agents -->
      <div v-if="isAdmin" class="sidebar-section">
        <button
          class="sidebar-collapse-btn"
          @click="$emit('toggle-filter', 'agents')"
        >
          <span>{{ $t('AGENDA.SIDEBAR.AGENTS') }}</span>
          <i
            :class="
              expandedFilters.agents
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
        <div v-if="expandedFilters.agents" class="filter-content">
          <div
            v-for="agent in visibleAgentList"
            :key="agent.id"
            class="agent-item"
            @click="$emit('toggle-agent', agent.id)"
          >
            <span
              class="agent-dot"
              :style="{
                backgroundColor: hiddenAgents.includes(agent.id)
                  ? 'transparent'
                  : agent.color,
                borderColor: agent.color,
                borderStyle: 'solid',
                borderWidth: '2px',
              }"
            />
            <span class="agent-name">{{ agent.name }}</span>
          </div>
        </div>
      </div>

      <!-- Priority -->
      <div class="sidebar-section">
        <button
          class="sidebar-collapse-btn"
          @click="$emit('toggle-filter', 'priority')"
        >
          <span>{{ $t('AGENDA.SIDEBAR.PRIORITY') }}</span>
          <i
            :class="
              expandedFilters.priority
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
        <div v-if="expandedFilters.priority" class="filter-content">
          <div
            v-for="p in priorityOptions"
            :key="p.value"
            class="agent-item"
            @click="$emit('toggle-priority', p.value)"
          >
            <span
              class="agent-dot"
              :style="{
                backgroundColor: hiddenPriorities.includes(p.value)
                  ? 'transparent'
                  : getPriorityColor(p.value),
                borderColor: getPriorityColor(p.value),
                borderStyle: 'solid',
                borderWidth: '2px',
              }"
            />
            <span class="agent-name">{{ p.label }}</span>
          </div>
        </div>
      </div>

      <!-- Event Type -->
      <div class="sidebar-section">
        <button
          class="sidebar-collapse-btn"
          @click="$emit('toggle-filter', 'eventType')"
        >
          <span>{{ $t('AGENDA.SIDEBAR.EVENT_TYPE') }}</span>
          <i
            :class="
              expandedFilters.eventType
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
        <div v-if="expandedFilters.eventType" class="filter-content">
          <div
            v-for="type in eventTypeOptions"
            :key="type.value"
            class="agent-item"
            @click="$emit('toggle-event-type', type.value)"
          >
            <span
              class="agent-dot"
              :style="{
                backgroundColor: hiddenEventTypes.includes(type.value)
                  ? 'transparent'
                  : 'rgb(var(--slate-8))',
                borderColor: 'rgb(var(--slate-8))',
                borderStyle: 'solid',
                borderWidth: '2px',
              }"
            />
            <span class="agent-name">{{ type.label }}</span>
          </div>
        </div>
      </div>

      <!-- Treatments -->
      <div class="sidebar-section">
        <button
          class="sidebar-collapse-btn"
          @click="$emit('toggle-filter', 'treatments')"
        >
          <span>{{ $t('AGENDA.SIDEBAR.TREATMENTS') }}</span>
          <i
            :class="
              expandedFilters.treatments
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
        <div v-if="expandedFilters.treatments" class="filter-content">
          <div
            v-for="tr in treatmentOptions"
            :key="typeof tr === 'string' ? tr : tr.id"
            class="agent-item"
            @click="$emit('toggle-treatment', typeof tr === 'string' ? tr : tr.name)"
          >
            <span
              class="agent-dot"
              :style="{
                backgroundColor: hiddenTreatments.includes(
                  typeof tr === 'string' ? tr : tr.name
                )
                  ? 'transparent'
                  : tr.color || 'rgb(var(--slate-8))',
                borderColor: tr.color || 'rgb(var(--slate-8))',
                borderStyle: 'solid',
                borderWidth: '2px',
              }"
            />
            <span class="agent-name">{{
              typeof tr === 'string' ? tr : tr.name
            }}</span>
          </div>
        </div>
      </div>

      <!-- Waiting List -->
      <div class="sidebar-section">
        <button
          class="sidebar-collapse-btn"
          @click="$emit('toggle-filter', 'waitingList')"
        >
          <span>
            {{ $t('WAITING_LIST.SIDEBAR_TITLE') }}
            <span
              v-if="waitingListEntries.length"
              class="wl-sidebar-pill"
            >
              {{ waitingListEntries.length }}
            </span>
          </span>
          <i
            :class="
              expandedFilters.waitingList
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
        <div v-if="expandedFilters.waitingList" class="filter-content">
          <!-- Empty state -->
          <div
            v-if="!waitingListEntries.length"
            class="agent-item wl-sidebar-empty"
          >
            <span class="agent-name">
              {{ $t('WAITING_LIST.SIDEBAR_EMPTY') }}
            </span>
          </div>
          <!-- Entries + inline detail popup -->
          <template
            v-for="entry in waitingListEntries"
            :key="entry.id"
          >
            <div
              class="agent-item wl-sidebar-entry"
              @click="$emit('show-wl-info', entry)"
            >
              <span class="wl-sidebar-dot wl-sidebar-dot--avatar">
                {{ (entry.contact_name || '?').charAt(0).toUpperCase() }}
              </span>
              <span class="agent-name">{{ entry.contact_name }}</span>
              <button
                class="wl-sidebar-remove"
                :aria-label="$t('WAITING_LIST.REMOVE_LABEL')"
                @click.stop="$emit('remove-wl', entry.id)"
              >
                <span class="i-ph-x" />
              </button>
            </div>
            <!-- Detail popup below clicked item -->
            <div
              v-if="wlInfoPopup && wlInfoPopup.entry.id === entry.id"
              class="wl-info-popup"
            >
              <button
                class="wl-info-close"
                @click.stop="$emit('close-wl-info')"
              >
                <span class="i-ph-x" />
              </button>
              <div class="wl-info-name">
                <span class="wl-sidebar-dot wl-sidebar-dot--avatar wl-info-avatar">
                  {{ (entry.contact_name || '?').charAt(0).toUpperCase() }}
                </span>
                {{ entry.contact_name }}
              </div>
              <div class="wl-info-row">
                <span class="i-ph-clock wl-info-icon" />
                <span>
                  <strong>Período:</strong>
                  {{ getPeriodLabel(entry.period) }}
                </span>
              </div>
              <div v-if="entry.specific_time" class="wl-info-row">
                <span class="i-ph-alarm wl-info-icon" />
                <span>
                  <strong>Horário:</strong>
                  {{ entry.specific_time }}
                </span>
              </div>
              <div
                v-if="entry.preferred_days && entry.preferred_days.length"
                class="wl-info-row"
              >
                <span class="i-ph-calendar-dots wl-info-icon" />
                <span>
                  <strong>Dias:</strong>
                  {{ entry.preferred_days.map(d => getDowLabel(d)).join(', ') }}
                </span>
              </div>
              <div v-if="entry.notes" class="wl-info-row">
                <span class="i-ph-note wl-info-icon" />
                <span><strong>Obs:</strong> {{ entry.notes }}</span>
              </div>
            </div>
          </template>
        </div>
      </div>
    </div>

</template>

<style scoped>
.agenda-sidebar {
  width: 230px;
  flex-shrink: 0;
  height: 100%;
  max-height: 100%;
  border-left: 1px solid rgb(var(--border-strong));
  background: rgb(var(--surface-1));
  overflow-y: auto;
  padding: 12px 10px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.sidebar-section {
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  background: rgb(var(--surface-1));
  overflow: hidden;
  flex-shrink: 0;
}

.sidebar-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 10px 12px 4px;
}

.sidebar-collapse-btn {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  padding: 10px 12px;
  border: none;
  background: transparent;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  cursor: pointer;
  transition: background 0.12s;
}

.sidebar-collapse-btn:hover {
  background: rgb(var(--slate-3));
}

.sidebar-collapse-btn i {
  width: 14px;
  height: 14px;
  color: rgb(var(--slate-9));
}

.filter-content {
  padding: 0 6px 8px;
}

.agent-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 10px;
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.1s;
}

.agent-item:hover {
  background: rgb(var(--slate-3));
}

.agent-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}

.agent-name {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Mini calendar */
.mini-calendar {
  padding: 6px 8px 8px;
}

.mini-cal-header {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  margin-bottom: 2px;
}

.mini-day-label {
  text-align: center;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-9));
  text-transform: uppercase;
}

.mini-cal-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 2px;
}

.mini-day {
  text-align: center;
  @apply text-sm;
  color: rgb(var(--slate-12));
  padding: 4px 0;
  border-radius: 4px;
  cursor: pointer;
  transition: background 0.1s;
}

.mini-day:hover {
  background: rgb(var(--slate-4));
}

.mini-day.other-month {
  color: rgb(var(--slate-7));
}

.mini-day.today {
  background: rgb(var(--blue-9));
  color: #fff;
  font-weight: 700;
}

.mini-day.selected {
  background: rgb(var(--slate-4));
  font-weight: 600;
}

/* Waiting list sidebar */
.wl-sidebar-pill {
  background: rgba(99, 102, 241, 0.15);
  color: #818cf8;
  @apply text-sm;
  font-weight: 700;
  padding: 2px 6px;
  border-radius: 8px;
  margin-left: 6px;
}

.wl-sidebar-empty {
  opacity: 0.5;
  cursor: default;
}

.wl-sidebar-dot--avatar {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  font-weight: 700;
  background: rgba(99, 102, 241, 0.15);
  color: #818cf8;
  flex-shrink: 0;
}

.wl-sidebar-entry {
  cursor: pointer;
}

.wl-sidebar-remove {
  margin-left: auto;
  background: none;
  border: none;
  color: rgb(var(--slate-8));
  cursor: pointer;
  @apply text-sm;
  transition: color 0.12s;
  padding: 2px;
}

.wl-sidebar-remove:hover {
  color: #dc2626;
}

/* WL info popup */
.wl-info-popup {
  position: relative;
  margin: 6px 0 4px;
  padding: 10px 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  @apply text-sm;
  color: rgb(var(--slate-12));
}

.wl-info-close {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 16px;
  height: 16px;
  background: transparent;
  border: none;
  cursor: pointer;
  color: rgb(var(--slate-8));
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-sm;
  border-radius: 3px;
  transition: color 0.12s;
}

.wl-info-close:hover {
  color: rgb(var(--slate-12));
}

.wl-info-name {
  display: flex;
  align-items: center;
  gap: 6px;
  font-weight: 600;
  @apply text-sm;
  margin-bottom: 8px;
}

.wl-info-avatar {
  width: 22px !important;
  height: 22px !important;
  font-size: 9px !important;
}

.wl-info-row {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  margin-bottom: 4px;
  line-height: 1.4;
  @apply text-sm;
}

.wl-info-icon {
  flex-shrink: 0;
  margin-top: 1px;
  color: #6366f1;
  @apply text-sm;
}

/* Mobile overrides */
.mobile-sidebar-overlay {
  display: none;
}

@media (max-width: 767px) {
  .mobile-sidebar-overlay {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    z-index: 100;
    backdrop-filter: blur(2px);
  }

  .agenda-sidebar {
    position: fixed !important;
    right: -300px;
    top: 0;
    bottom: 0;
    width: 280px;
    z-index: 101 !important;
    transition: right 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    box-shadow: -4px 0 24px rgba(0, 0, 0, 0.15);
    border-left: 1px solid rgb(var(--border-strong));
  }

  .agenda-sidebar.mobile-open {
    right: 0 !important;
  }
}

@media (min-width: 768px) and (max-width: 1023px) {
  .mobile-sidebar-overlay {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    z-index: 100;
  }

  .agenda-sidebar {
    position: fixed !important;
    right: -300px;
    top: 0;
    bottom: 0;
    width: 280px;
    z-index: 101 !important;
    transition: right 0.3s ease;
    box-shadow: -4px 0 16px rgba(0, 0, 0, 0.1);
  }

  .agenda-sidebar.mobile-open {
    right: 0 !important;
  }
}

@media (min-width: 1024px) and (max-width: 1279px) {
  .mobile-sidebar-overlay {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    z-index: 100;
  }

  .agenda-sidebar {
    position: fixed !important;
    right: -300px;
    top: 0;
    bottom: 0;
    width: 280px;
    z-index: 101 !important;
    transition: right 0.3s ease;
    box-shadow: -4px 0 16px rgba(0, 0, 0, 0.1);
  }

  .agenda-sidebar.mobile-open {
    right: 0 !important;
  }
}
</style>
