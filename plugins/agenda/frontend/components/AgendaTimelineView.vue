<script>
import AgendaEventCard from './AgendaEventCard.vue';
import AgendaDragGhost from './AgendaDragGhost.vue';
import { parseEventDate, formatEventTime, getEventDurationInHours, getEventSizeTier } from '../utils/agenda-date.js';

export default {
  name: 'AgendaTimelineView',
  components: { AgendaEventCard, AgendaDragGhost },
  props: {
    viewMode: { type: String, required: true },
    layoutMode: { type: String, default: 'side-by-side' },
    activeAgents: { type: Array, default: () => [] },
    currentWeekDays: { type: Array, default: () => [] },
    currentDayObj: { type: Object, default: () => ({}) },
    dayHours: { type: Array, required: true },
    rowHeight: { type: Number, default: 80 },
    pixelsPerHour: { type: Number, default: 80 },
    agendaEvents: { type: Array, default: () => [] },
    agentList: { type: Array, default: () => [] },
    currentUserID: { type: [Number, String], default: null },
    isAdmin: { type: Boolean, default: false },
    currentTimeLineStyle: { type: Object, default: () => ({}) },
    // Drag state
    isDragging: { type: Boolean, default: false },
    draggingEvent: { type: Object, default: null },
    draggingEventId: { type: [Number, String], default: null },
    dragCurrentDayObj: { type: Object, default: null },
    dragCurrentStartsAt: { type: String, default: null },
    dragCurrentEndsAt: { type: String, default: null },
    dragGhostStyle: { type: Object, default: () => ({}) },
    // Resize state
    isResizing: { type: Boolean, default: false },
    resizingEventId: { type: [Number, String], default: null },
    resizingEventEndAt: { type: String, default: null },
    // Methods passed as props
    isHourBlocked: { type: Function, required: true },
    getWaitingListMatchForCell: { type: Function, required: true },
    getEventsForDay: { type: Function, required: true },
    calculateOverlaps: { type: Function, required: true },
    getEventBackground: { type: Function, required: true },
    getAgentColor: { type: Function, required: true },
    getStatusConfig: { type: Function, required: true },
    isEventLate: { type: Function, required: true },
    getDayBlockInfo: { type: Function, default: () => [] },
    isDarkTheme: { type: Boolean, default: true },
    canCreate: { type: Boolean, default: true },
    canCancel: { type: Boolean, default: true },
    canDrag: { type: Boolean, default: true },
    canEdit: { type: Boolean, default: true },
  },
  emits: [
    'click-cell',
    'click-event',
    'init-drag',
    'init-resize',
    'wl-cell-click',
    'quick-delete',
  ],
  computed: {
    columns() {
      if (this.viewMode === 'week') return this.currentWeekDays;
      return this.activeAgents;
    },
    dynamicColWidth() {
      if (this.viewMode === 'day' && this.activeAgents.length > 7) {
        return 'calc((100cqi - 64px) / 7)';
      }
      return '0px';
    },
    showTimeLine() {
      if (this.viewMode === 'week') return true;
      return this.isToday(this.currentDayObj);
    },
  },
  methods: {
    formatEventTime,
    getEventSizeTier,
    isToday(dayObj) {
      const n = new Date();
      return (
        dayObj.day === n.getDate() &&
        dayObj.month === n.getMonth() &&
        dayObj.year === n.getFullYear()
      );
    },
    getColumnEventsWithPositions(colItem) {
      let dayObj;
      if (this.viewMode === 'week') {
        dayObj = colItem;
      } else {
        dayObj = this.currentDayObj;
      }

      const dayEvents = this.getEventsForDay(dayObj);

      let filtered;
      if (this.viewMode === 'day') {
        filtered = dayEvents.filter(e => e.user_id === colItem.id);
      } else {
        filtered = dayEvents;
      }

      const withOverlaps = this.calculateOverlaps(filtered);

      return withOverlaps.map(event => {
        return {
          ...event,
          _style: this.getEventTimelineStyle(
            event,
            event.totalCols,
            event.colIdx
          ),
          _agentColor: this.getAgentColor(event),
          _bg: this.getEventBackground(event),
        };
      });
    },
    getEventTimelineStyle(event, totalCols, colIdx) {
      if (!event.starts_at || !event.ends_at) return {};
      const start = parseEventDate(event.starts_at);
      const topOffset =
        start.getHours() * this.pixelsPerHour +
        (start.getMinutes() / 60) * this.pixelsPerHour;

      let endAtForCalc = event.ends_at;
      if (
        this.isResizing &&
        this.resizingEventId === event.id &&
        this.resizingEventEndAt
      ) {
        endAtForCalc = this.resizingEventEndAt;
      }

      const durationHours = getEventDurationInHours(
        event,
        this.isResizing && this.resizingEventId === event.id
          ? endAtForCalc
          : null
      );
      const heightPx = Math.max(
        20,
        durationHours * this.pixelsPerHour - 4
      );

      const colCount = totalCols || 1;
      const idx = colIdx || 0;
      const colWidthPct = 100 / colCount;
      const leftPct = idx * colWidthPct;

      return {
        position: 'absolute',
        top: `${topOffset + 2}px`,
        height: `${heightPx}px`,
        left: `calc(${leftPct}% + 3px)`,
        width: `calc(${colWidthPct}% - 6px)`,
        background: this.getEventBackground(event),
        borderLeftColor: this.getAgentColor(event),
        zIndex: this.isDragging && this.draggingEventId === event.id ? 50 : 5,
      };
    },
    isDragInDay(dayObj) {
      if (!this.dragCurrentDayObj) return false;
      return (
        this.dragCurrentDayObj.day === dayObj.day &&
        this.dragCurrentDayObj.month === dayObj.month &&
        this.dragCurrentDayObj.year === dayObj.year
      );
    },
    isDragInAgentCol(agent) {
      if (!this.draggingEvent) return false;
      return this.draggingEvent.user_id === agent.id;
    },
    showDragGhostInCol(colItem) {
      if (!this.isDragging || !this.draggingEvent) return false;
      if (this.viewMode === 'week') {
        return this.isDragInDay(colItem);
      }
      return this.isDragInAgentCol(colItem);
    },
  },
};
</script>

<template>
  <div
    class="timeline-area"
    :class="[viewMode, layoutMode]"
    :style="{ '--dynamic-col-width': dynamicColWidth }"
  >
    <div class="timeline-internal-wrapper">
      <!-- Timeline Header -->
      <div ref="timelineHeaders" class="timeline-headers">
        
        <!-- Day View: Full day events (Holidays, Exceções) -->
        <div v-if="viewMode === 'day' && getDayBlockInfo(currentDayObj).some(b => b.type !== 'closed')" class="timeline-headers-row border-bottom-strong">
           <div class="time-header-spacer" />
           <div class="day-view-blocks-wrapper">
              <template v-for="(block, bIdx) in getDayBlockInfo(currentDayObj)" :key="bIdx">
                 <div v-if="block.type !== 'closed'"
                      class="header-block-banner" 
                      :class="[`block-type-${block.type}`, { 'is-past': block.isPast }]">
                    {{ block.title }}
                 </div>
              </template>
           </div>
        </div>

        <!-- Normal Headers (Week Days or Agents) -->
        <div class="timeline-headers-row">
          <div class="time-header-spacer" />
          <template v-if="viewMode === 'week'">
            <div
              v-for="(dayObj, idx) in currentWeekDays"
              :key="idx"
              class="timeline-day-header"
              :class="{ 'is-today': isToday(dayObj) }"
            >
              <div style="display: flex; align-items: center; gap: 4px;">
                <span class="day-str">{{ dayObj.label }}</span>
                <i 
                  v-if="getDayBlockInfo(dayObj).some(b => b.type === 'closed')" 
                  class="i-lucide-lock text-n-slate-8 text-xs" 
                  title="Dias fechado"
                />
              </div>
              <div class="day-num-wrap">
                <div class="day-num" :class="{ today: isToday(dayObj) }">
                  {{ dayObj.day }}
                </div>
              </div>
              <div class="header-day-blocks" v-if="getDayBlockInfo(dayObj).some(b => b.type !== 'closed')">
                 <template v-for="(block, bIdx) in getDayBlockInfo(dayObj)" :key="bIdx">
                    <div v-if="block.type !== 'closed'"
                         class="header-block-banner" 
                         :class="[`block-type-${block.type}`, { 'is-past': block.isPast }]">
                       {{ block.title }}
                    </div>
                 </template>
              </div>
            </div>
          </template>
          <template v-else>
            <div
              v-for="agent in activeAgents"
              :key="agent.id"
              class="timeline-day-header"
              :class="{ 'is-today': isToday(currentDayObj) }"
            >
              <div class="agent-header">
                <div
                  class="agent-color-dot"
                  :style="{ backgroundColor: agent.color }"
                />
                <span class="agent-name-label">{{ agent.name }}</span>
              </div>
            </div>
          </template>
        </div>
      </div>

      <div class="timeline-grid-wrapper">
        <!-- Background Grid Layer -->
        <div class="timeline-grid-background">
          <div
            v-for="hour in dayHours"
            :key="hour"
            class="timeline-row"
            :style="{ height: `${rowHeight}px` }"
          >
            <div class="time-label">{{ hour }}</div>
            <template v-if="viewMode === 'week'">
              <div
                v-for="(dayObj, idx) in currentWeekDays"
                :key="idx"
                class="timeline-cell"
                :class="{
                  'cell-blocked': isHourBlocked(dayObj, hour),
                  'cell-wl-match':
                    !isHourBlocked(dayObj, hour) &&
                    getWaitingListMatchForCell(dayObj, hour).length > 0,
                }"
                @click="$emit('click-cell', { dayObj, hour })"
              >
                <div
                  v-if="isHourBlocked(dayObj, hour) && !['Passado', 'Fechado'].includes(isHourBlocked(dayObj, hour))"
                  class="blocked-slot-overlay"
                >
                  <i class="i-lucide-lock blocked-slot-icon" />
                  <span class="blocked-slot-text">{{ isHourBlocked(dayObj, hour) === true ? 'Indisponível' : isHourBlocked(dayObj, hour) }}</span>
                </div>
                <div
                  v-else-if="
                    getWaitingListMatchForCell(dayObj, hour).length > 0
                  "
                  class="wl-cell-actions"
                >
                  <button
                    class="wl-cell-btn"
                    title="Criar novo evento"
                    @click.stop="$emit('click-cell', { dayObj, hour })"
                  >
                    <span class="i-ph-pencil-simple" />
                  </button>
                  <button
                    class="wl-cell-btn wl-cell-btn--wl"
                    title="Agendar paciente da lista de espera"
                    @click.stop="$emit('wl-cell-click', { $event, dayObj, hour })"
                  >
                    <span class="i-ph-clock-countdown" />
                  </button>
                </div>
              </div>
            </template>
            <template v-else>
              <div
                v-for="agent in activeAgents"
                :key="agent.id"
                class="timeline-cell day-cell"
                :class="{
                  'cell-blocked': isHourBlocked(currentDayObj, hour),
                }"
                @click="$emit('click-cell', { dayObj: currentDayObj, hour, agent })"
              >
                <div
                  v-if="isHourBlocked(currentDayObj, hour) && isHourBlocked(currentDayObj, hour) !== 'Passado'"
                  class="blocked-slot-overlay"
                >
                  <i class="i-lucide-lock blocked-slot-icon" />
                  <span class="blocked-slot-text">{{ isHourBlocked(currentDayObj, hour) === true ? 'Indisponível' : isHourBlocked(currentDayObj, hour) }}</span>
                </div>
              </div>
            </template>
          </div>
        </div>

        <!-- Events overlay layer -->
        <div class="timeline-events-layer">
          <div class="time-label-spacer" />
          <!-- Current time line -->
          <div
            v-if="showTimeLine"
            class="current-time-line"
            :style="currentTimeLineStyle"
          >
            <div class="current-time-dot" />
          </div>

          <div
            v-for="(colItem, dIdx) in columns"
            :key="dIdx"
            class="day-events-column"
          >
            <AgendaEventCard
              v-for="event in getColumnEventsWithPositions(colItem)"
              :key="event.id"
              :event="event"
              :card-style="event._style"
              :agent-color="event._agentColor"
              :is-resizing-this="isResizing && resizingEventId === event.id"
              :is-dragging-this="isDragging && draggingEventId === event.id"
              :is-late="isEventLate(event)"
              :resizing-end-at="resizingEventEndAt"
              :layout-mode="layoutMode"
              :can-cancel="canCancel"
              :can-drag="canDrag"
              :can-edit="canEdit"
              @click="$emit('click-event', { event, $event })"
              @quick-delete="$emit('quick-delete', event)"
              @mousedown-drag="$emit('init-drag', { event, $event })"
              @mousedown-resize="$emit('init-resize', { event, $event })"
            />

            <!-- Drag ghost -->
            <AgendaDragGhost
              v-if="showDragGhostInCol(colItem)"
              :event="draggingEvent"
              :ghost-style="dragGhostStyle"
              :drag-starts-at="dragCurrentStartsAt"
              :drag-ends-at="dragCurrentEndsAt"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.timeline-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  background: rgb(var(--surface-1));
  overflow-y: auto;
  overflow-x: auto;
  container-type: inline-size;
  container-name: timelineArea;
}

.timeline-internal-wrapper {
  display: flex;
  flex-direction: column;
  min-width: 100%;
  width: max-content;
  position: relative;
}

.timeline-headers {
  display: flex;
  flex-direction: column;
  border-bottom: 1px solid rgb(var(--border-strong));
  background: rgb(var(--slate-2));
  min-width: 100%;
  box-sizing: border-box;
  position: sticky;
  top: 0;
  z-index: 40;
}

.timeline-headers-row {
  display: flex;
  align-items: stretch;
  width: 100%;
}

.border-bottom-strong {
  border-bottom: 1px solid rgb(var(--border-strong));
}

.time-header-spacer {
  width: 64px;
  flex-shrink: 0;
  text-align: center;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  border-right: 1px solid rgb(var(--border-strong));
  padding: 12px 0;
  box-sizing: border-box;
  position: sticky;
  left: 0;
  z-index: 10;
  background: rgb(var(--slate-2));
}

.timeline-day-header {
  flex: 1;
  text-align: center;
  padding: 12px 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  border-right: 1px solid rgb(var(--border-strong));
  box-sizing: border-box;
  min-width: var(--dynamic-col-width, 0px) !important;
  overflow: hidden;
  position: relative;
}

.header-locked-icon {
  position: absolute;
  top: 8px;
  right: 8px;
  color: rgb(var(--slate-8));
  font-size: 14px;
}

.day-str {
  @apply text-sm;
  text-transform: uppercase;
  font-weight: 600;
  color: rgb(var(--slate-10));
}

.day-num-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
}

.day-num {
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
}

.day-num.today {
  background: #3b82f6;
  color: #fff;
}

.header-day-blocks {
  display: flex;
  flex-direction: column;
  gap: 2px;
  width: 100%;
  padding: 0 4px;
  margin-top: 4px;
  box-sizing: border-box;
}

.day-view-blocks-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 2px;
  padding: 4px;
}

.header-block-banner {
  @apply text-sm;
  font-weight: 600;
  padding: 3px 6px;
  border-radius: 4px;
  color: #fff;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: center;
}

.block-type-holiday {
  background: #10b981;
}

.block-type-holiday.is-past {
  background: rgba(16, 185, 129, 0.35);
  color: rgba(6, 95, 70, 0.9);
}

.block-type-exception {
  background: #f59e0b;
}

.block-type-exception.is-past {
  background: rgba(245, 158, 11, 0.35);
  color: rgba(146, 64, 14, 0.9);
}

.block-type-closed {
  background: #9ca3af;
}

.block-type-closed.is-past {
  background: rgba(156, 163, 175, 0.35);
  color: rgba(55, 65, 81, 0.9);
}

.dark .block-type-holiday { background: rgba(16, 185, 129, 0.85); color: #fff; }
.dark .block-type-holiday.is-past { background: rgba(16, 185, 129, 0.25); color: rgba(16, 185, 129, 0.9); }
.dark .block-type-exception { background: rgba(245, 158, 11, 0.85); color: #fff; }
.dark .block-type-exception.is-past { background: rgba(245, 158, 11, 0.25); color: rgba(251, 191, 36, 0.9); }
.dark .block-type-closed { background: rgba(100, 116, 139, 0.5); color: rgba(241, 245, 249, 0.9); }
.dark .block-type-closed.is-past { background: rgba(100, 116, 139, 0.25); color: rgba(148, 163, 184, 0.8); }

.agent-header {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
}

.agent-color-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
}

.agent-name-label {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}

.timeline-grid-wrapper {
  position: relative;
  min-width: 100%;
}

.timeline-grid-background {
  display: flex;
  flex-direction: column;
}

.timeline-row {
  display: flex;
  border-bottom: 1px solid rgb(var(--border-strong));
  position: relative;
}

.time-label {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 64px;
  flex-shrink: 0;
  border-right: 1px solid rgb(var(--border-strong));
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  box-sizing: border-box;
  position: sticky;
  left: 0;
  z-index: 10;
  background: rgb(var(--surface-1));
}

.timeline-cell {
  flex: 1;
  border-right: 1px solid rgb(var(--border-strong));
  position: relative;
  cursor: pointer;
  padding: 4px;
  box-sizing: border-box;
  min-width: 0;
}

.timeline-cell:hover {
  background: rgb(var(--slate-2));
}

/* Blocked slot */
.timeline-cell.cell-blocked {
  cursor: not-allowed;
  background: repeating-linear-gradient(
    -45deg,
    transparent,
    transparent 10px,
    rgba(var(--slate-12), 0.05) 10px,
    rgba(var(--slate-12), 0.06) 11px
  ) !important;
  position: relative;
}

.timeline-cell.cell-blocked:hover {
  background: repeating-linear-gradient(
    -45deg,
    transparent,
    transparent 10px,
    rgba(var(--slate-12), 0.08) 10px,
    rgba(var(--slate-12), 0.09) 11px
  ) !important;
}

.blocked-slot-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: row;
  gap: 6px;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}

.blocked-slot-icon {
  width: 12px;
  height: 12px;
  color: rgb(var(--slate-8));
}

.blocked-slot-text {
  @apply text-xs;
  font-weight: 500;
  color: rgb(var(--slate-8));
  opacity: 0.8;
}

/* WL matched cells */
.cell-wl-match {
  background: rgba(34, 197, 94, 0.07) !important;
  position: relative;
}

.cell-wl-match::after {
  content: '';
  position: absolute;
  inset: 2px;
  border: 1px dashed rgba(34, 197, 94, 0.45);
  border-radius: 3px;
  pointer-events: none;
}

.wl-cell-actions {
  position: absolute;
  bottom: 4px;
  right: 4px;
  display: flex;
  gap: 4px;
  opacity: 0;
  transition: opacity 0.12s;
  z-index: 2;
}

.cell-wl-match:hover .wl-cell-actions {
  opacity: 1;
}

.wl-cell-btn {
  width: 28px;
  height: 28px;
  border: none;
  border-radius: 6px;
  background: rgba(34, 197, 94, 0.18);
  color: rgba(34, 197, 94, 0.9);
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-sm;
  cursor: pointer;
  transition: background 0.12s, color 0.12s, transform 0.1s;
}

.wl-cell-btn:hover {
  background: rgba(34, 197, 94, 0.28);
  color: rgba(34, 197, 94, 1);
  transform: scale(1.1);
}

.wl-cell-btn--wl {
  background: rgba(99, 102, 241, 0.15);
  color: rgba(99, 102, 241, 0.85);
}

.wl-cell-btn--wl:hover {
  background: rgba(99, 102, 241, 0.28);
  color: rgba(99, 102, 241, 1);
}

/* Events overlay */
.timeline-events-layer {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  pointer-events: none;
  z-index: 5;
}

.day-events-column {
  flex: 1;
  position: relative;
  height: 1920px;
  border-right: 1px solid transparent;
  min-width: var(--dynamic-col-width, 0px) !important;
}

.time-label-spacer {
  width: 64px;
  flex-shrink: 0;
  box-sizing: border-box;
  position: sticky;
  left: 0;
  z-index: 10;
}

.current-time-line {
  position: absolute;
  left: 64px;
  right: 0;
  height: 2px;
  background-color: rgb(var(--blue-9));
  z-index: 20;
  pointer-events: none;
}

.current-time-dot {
  position: absolute;
  left: -4px;
  top: -4px;
  width: 10px;
  height: 10px;
  background-color: rgb(var(--blue-9));
  border-radius: 50%;
}

/* Mobile responsive fixes */
@media (max-width: 767px) {
  .blocked-slot-text {
    display: none !important;
  }
}
</style>
