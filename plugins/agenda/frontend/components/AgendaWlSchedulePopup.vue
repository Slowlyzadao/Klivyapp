<script>
import { PERIOD_SHORT_LABELS } from '../utils/agenda-constants.js';

export default {
  name: 'AgendaWlSchedulePopup',
  props: {
    show: { type: Boolean, default: false },
    cellPopup: { type: Object, default: null },
  },
  emits: ['close', 'select'],
  methods: {
    getPeriodLabel(period) {
      return PERIOD_SHORT_LABELS[period] || period;
    },
    getInitial(name) {
      return (name || '?').charAt(0).toUpperCase();
    },
  },
};
</script>

<template>
  <div
    v-if="show && cellPopup"
    class="wl-schedule-overlay"
    @click.self="$emit('close')"
  >
    <div
      class="wl-schedule-modal"
      :style="{ top: cellPopup.top + 'px', left: cellPopup.left + 'px' }"
      @click.stop
    >
      <div class="wl-schedule-header">
        <span class="i-ph-clock-countdown wl-schedule-header-icon" />
        <div>
          <div class="wl-schedule-title">Lista de espera</div>
          <div class="wl-schedule-subtitle">
            {{ cellPopup.hour }} ·
            {{ cellPopup.dayObj && cellPopup.dayObj.label }}
          </div>
        </div>
        <button class="wl-schedule-close" @click="$emit('close')">
          <span class="i-ph-x" />
        </button>
      </div>
      <div class="wl-schedule-list">
        <div
          v-for="entry in cellPopup.entries || []"
          :key="entry.id"
          class="wl-schedule-item"
          @click="$emit('select', entry)"
        >
          <span class="wl-schedule-avatar">
            {{ getInitial(entry.contact_name) }}
          </span>
          <div class="wl-schedule-item-info">
            <div class="wl-schedule-item-name">{{ entry.contact_name }}</div>
            <div class="wl-schedule-item-meta">
              {{ getPeriodLabel(entry.period) }}
              <span v-if="entry.specific_time">· {{ entry.specific_time }}</span>
            </div>
          </div>
          <span class="i-ph-arrow-right wl-schedule-arrow" />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.wl-schedule-overlay {
  position: fixed;
  inset: 0;
  z-index: 300;
  background: transparent;
}

.wl-schedule-modal {
  position: fixed;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  width: 300px;
  max-height: 400px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.18);
  z-index: 301;
}

.wl-schedule-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 14px;
  border-bottom: 1px solid rgb(var(--slate-4));
}

.wl-schedule-header-icon {
  font-size: 22px;
  color: #6366f1;
  flex-shrink: 0;
}

.wl-schedule-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.wl-schedule-subtitle {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}

.wl-schedule-close {
  margin-left: auto;
  width: 28px;
  height: 28px;
  border: none;
  background: transparent;
  cursor: pointer;
  color: rgb(var(--slate-9));
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  @apply text-sm;
  transition: background 0.12s, color 0.12s;
}

.wl-schedule-close:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.wl-schedule-list {
  overflow-y: auto;
  padding: 8px;
}

.wl-schedule-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  border-radius: 10px;
  cursor: pointer;
  transition: background 0.12s;
}

.wl-schedule-item:hover {
  background: rgb(var(--slate-3));
}

.wl-schedule-avatar {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: rgba(99, 102, 241, 0.12);
  color: #6366f1;
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-sm;
  font-weight: 700;
  flex-shrink: 0;
}

.wl-schedule-item-info {
  flex: 1;
  min-width: 0;
}

.wl-schedule-item-name {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}

.wl-schedule-item-meta {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}

.wl-schedule-arrow {
  @apply text-sm;
  color: rgb(var(--slate-7));
}

@media (max-width: 767px) {
  .wl-schedule-modal {
    position: fixed !important;
    bottom: 0 !important;
    left: 0 !important;
    right: 0 !important;
    top: auto !important;
    width: 100% !important;
    border-radius: 20px 20px 0 0 !important;
    max-height: 60vh !important;
  }
}
</style>
