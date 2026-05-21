<script>
import { formatEventTime } from '../utils/agenda-date.js';

export default {
  name: 'AgendaMonthView',
  props: {
    calendarWeeks: { type: Array, required: true },
    dayHeaders: { type: Array, required: true },
    eventsMap: { type: Object, default: () => ({}) },
    getDayBlockInfo: { type: Function, default: () => [] },
    isDayBlocked: { type: Function, default: () => false },
    isDayInPast: { type: Function, default: () => false },
  },
  emits: ['click-day', 'click-event', 'view-day'],
  methods: {
    formatEventTime,
    isToday(dayObj) {
      const n = new Date();
      return (
        dayObj.day === n.getDate() &&
        dayObj.month === n.getMonth() &&
        dayObj.year === n.getFullYear()
      );
    },
    dayKey(dayObj) {
      return `${dayObj.year}-${dayObj.month}-${dayObj.day}`;
    },
    getDayEvents(dayObj) {
      return this.eventsMap[this.dayKey(dayObj)] || [];
    },
    getDowLabel(dayObj) {
      const date = new Date(dayObj.year, dayObj.month, dayObj.day);
      return this.dayHeaders[date.getDay()] || '';
    },
    handleDayClick(dayObj) {
      if (this.isDayBlocked(dayObj) || this.isDayInPast(dayObj)) return;
      this.$emit('click-day', dayObj);
    }
  },
};
</script>

<template>
  <div class="calendar-area">
    <div class="calendar-day-headers">
      <div
        v-for="(day, index) in dayHeaders"
        :key="index"
        class="day-header"
        :class="{ 'is-weekend': index === 0 || index === 6 }"
      >
        {{ day }}
      </div>
    </div>
    <div class="calendar-grid">
      <div
        v-for="(week, wIdx) in calendarWeeks"
        :key="wIdx"
        class="calendar-week"
      >
        <div
          v-for="(dayObj, dIdx) in week"
          :key="`${dayObj.year}-${dayObj.month}-${dayObj.day}`"
          class="calendar-cell"
          :class="{
            'other-month': !dayObj.isCurrentMonth,
            'is-today': isToday(dayObj),
            'is-weekend': dIdx === 0 || dIdx === 6,
            'cell-blocked': isDayBlocked(dayObj) || isDayInPast(dayObj)
          }"
          @click="handleDayClick(dayObj)"
        >
          <div
            v-if="isDayBlocked(dayObj)"
            class="month-blocked-overlay"
          >
            <i class="i-lucide-lock blocked-icon" />
          </div>
          <div class="cell-header">
            <span class="cell-day-label">{{ getDowLabel(dayObj) }}</span>
            <span
              class="day-number"
              :class="{ today: isToday(dayObj) }"
            >
              {{ dayObj.day }}
            </span>
            <button
              v-if="!isDayBlocked(dayObj) && !isDayInPast(dayObj)"
              class="cell-add-btn"
              @click.stop="handleDayClick(dayObj)"
            >
              <i class="i-lucide-plus" />
            </button>
          </div>
          <div class="cell-day-blocks" v-if="getDayBlockInfo(dayObj).some(b => b.type !== 'closed')">
             <template v-for="(block, bIdx) in getDayBlockInfo(dayObj)" :key="bIdx">
               <div v-if="block.type !== 'closed'"
                    class="day-block-banner" 
                    :class="[`block-type-${block.type}`, { 'is-past': block.isPast }]">
                  {{ block.title }}
               </div>
             </template>
          </div>
          <div class="cell-events">
            <div
              v-for="event in getDayEvents(dayObj).slice(0, 3)"
              :key="event.id"
              class="event-chip"
              :style="{ '--dot-color': event._borderColor }"
              @click.stop="$emit('click-event', { event, $event })"
            >
              <span class="event-dot" />
              <span class="event-title">{{ event.title }}</span>
            </div>
            <button
              v-if="getDayEvents(dayObj).length > 3"
              type="button"
              class="event-more"
              :title="`Ver todos os ${getDayEvents(dayObj).length} eventos do dia`"
              @click.stop="$emit('view-day', dayObj)"
            >
              {{ `+${getDayEvents(dayObj).length - 3} ${$t('AGENDA.MORE')}` }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.calendar-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: auto;
  container-type: inline-size;
}

.calendar-day-headers {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  border-bottom: 1px solid rgb(var(--border-strong));
  background: rgb(var(--slate-2));
}

.day-header {
  text-align: center;
  padding: 10px 0;
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
  color: rgb(var(--slate-10));
  letter-spacing: 0.5px;
}

/* Weekend headers in red — matches reference */
.day-header.is-weekend {
  color: #dc2626;
}

.calendar-cell.is-weekend .day-number:not(.today) {
  color: #dc2626;
}

.calendar-grid {
  display: flex;
  flex-direction: column;
  flex: 1;
}

.calendar-week {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  flex: 1;
  border-bottom: 1px solid rgb(var(--border-strong));
}

.calendar-cell {
  border-right: 1px solid rgb(var(--border-strong));
  padding: 4px 5px;
  display: flex;
  flex-direction: column;
  min-height: 90px;
  overflow: hidden;
  cursor: pointer;
  transition: background 0.12s;
  position: relative;
}

.calendar-cell.cell-blocked {
  background: repeating-linear-gradient(
    -45deg,
    rgb(var(--slate-2)),
    rgb(var(--slate-2)) 7px,
    rgb(var(--slate-3)) 7px,
    rgb(var(--slate-3)) 9px
  ) !important;
  cursor: not-allowed;
}

.calendar-cell.cell-blocked:hover {
  background: repeating-linear-gradient(
    -45deg,
    rgb(var(--slate-2)),
    rgb(var(--slate-2)) 7px,
    rgb(var(--slate-4)) 7px,
    rgb(var(--slate-4)) 9px
  ) !important;
}

.month-blocked-overlay {
  position: absolute;
  top: 8px;
  right: 8px;
  pointer-events: none;
  opacity: 0.6;
}
.month-blocked-overlay .blocked-icon {
  font-size: 14px;
  color: rgb(var(--slate-8));
}

.calendar-cell {
  transition: background 0.15s ease-in-out;
}

.calendar-cell:hover {
  background: rgba(59, 130, 246, 0.10);
}

.calendar-cell.other-month {
  opacity: 0.35;
}

.calendar-cell.is-today {
  background: rgba(var(--blue-9), 0.04);
}

.cell-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 2px 0 4px;
}

.cell-day-label {
  display: none; /* Hidden on desktop */
}

.day-number {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  text-align: center;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
}

.day-number.today {
  background: #3b82f6;
  color: #fff;
}

.cell-add-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border: none;
  border-radius: 6px;
  background: rgba(var(--slate-12), 0.05); /* Fundo com contraste leve sobre o slate-2 do cell */
  color: rgb(var(--slate-9));
  cursor: pointer;
  opacity: 0;
  transition: opacity 0.15s, background 0.15s, color 0.15s;
  padding: 0 !important;
}

.cell-add-btn i {
  width: 18px;
  height: 18px;
}

.calendar-cell:hover .cell-add-btn {
  opacity: 1;
  background: rgba(59, 130, 246, 0.12) !important;
  color: rgb(var(--blue-9)) !important;
}

.cell-add-btn:hover {
  background: rgba(59, 130, 246, 0.22) !important;
}

.cell-day-blocks {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-bottom: 4px;
}

.day-block-banner {
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
  background: #10b981; /* Verde esmeralda para feriados */
}

.block-type-holiday.is-past {
  background: rgba(16, 185, 129, 0.35); /* Verde translúcido para passado */
  color: rgba(6, 95, 70, 0.9); /* Tom mais escuro para o texto */
}

.block-type-exception {
  background: #f59e0b; /* Laranja/âmbar para exceções */
}

.block-type-exception.is-past {
  background: rgba(245, 158, 11, 0.35);
  color: rgba(146, 64, 14, 0.9);
}

.block-type-closed {
  background: #9ca3af; /* Cinza para dias completamente fechados */
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

.cell-events {
  display: flex;
  flex-direction: column;
  gap: 2px;
  overflow: hidden;
  flex: 1;
}

/* List-style minimal: colored dot + title, no background pill */
.event-chip {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 2px 6px;
  border-radius: 4px;
  cursor: pointer;
  white-space: nowrap;
  overflow: hidden;
  transition: background 0.12s;
  min-height: 20px;
}

.event-chip:hover {
  background: rgba(0, 0, 0, 0.05);
}

.event-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--dot-color, rgb(var(--blue-9)));
  flex-shrink: 0;
}

.event-title {
  color: rgb(var(--slate-12));
  font-weight: 500;
  font-size: 12px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
  min-width: 0;
}

.event-more {
  @apply text-sm;
  color: rgb(var(--blue-9));
  text-align: center;
  padding: 2px 6px;
  border-radius: 4px;
  cursor: pointer;
  font-weight: 600;
  transition: background 0.12s;
  background: transparent;
  border: none;
  width: 100%;
  font-family: inherit;
}

.event-more:hover {
  background: rgba(var(--blue-9), 0.08);
}

.event-more:focus-visible {
  outline: 2px solid rgb(var(--blue-9));
  outline-offset: 1px;
}

/* Mobile responsive */
@media (max-width: 767px) {
  .calendar-day-headers {
    display: none !important;
  }

  .calendar-grid {
    display: flex !important;
    flex-direction: column !important;
    overflow-y: auto !important;
    padding: 8px !important;
    gap: 0 !important;
  }

  .calendar-week {
    display: flex !important;
    flex-direction: column !important;
    border: none !important;
  }

  .calendar-cell {
    min-height: auto !important;
    border: 1px solid rgb(var(--border-strong)) !important;
    margin-bottom: 6px !important;
    border-radius: 10px !important;
    padding: 8px 10px !important;
    overflow: visible !important;
  }

  .calendar-cell.other-month {
    display: none !important;
  }

  .month-blocked-overlay {
    top: 15px !important;
    right: 42px !important;
  }

  .cell-day-label {
    display: inline !important;
    @apply text-sm;
    font-weight: 700;
    color: rgb(var(--slate-9));
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-right: 6px;
  }

  .cell-header {
    margin-bottom: 6px;
    padding: 2px 0 6px !important;
    align-items: center;
  }

  .cell-events {
    padding: 0 !important;
    overflow: visible !important;
  }

  .event-chip {
    white-space: normal !important;
    height: auto !important;
    padding: 8px !important;
    min-height: 32px !important;
    border-radius: 6px !important;
    flex-wrap: wrap;
  }
}
</style>
