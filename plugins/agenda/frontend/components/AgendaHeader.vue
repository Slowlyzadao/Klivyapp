<script>
export default {
  name: 'AgendaHeader',
  props: {
    monthLabel: { type: String, required: true },
    viewMode: { type: String, required: true },
    showSummaryBar: { type: Boolean, default: false },
    showMobileSidebar: { type: Boolean, default: false },
    viewDropdownOpen: { type: Boolean, default: false },
    canCreate: { type: Boolean, default: true },
  },
  emits: [
    'prev',
    'next',
    'today',
    'set-view-mode',
    'toggle-summary',
    'refresh-summary',
    'toggle-sidebar',
    'new-event',
    'update:viewDropdownOpen',
  ],
  computed: {
    shortMonthLabel() {
      if (!this.monthLabel) return '';
      const parts = this.monthLabel.split(' ');
      if (parts.length >= 3) {
        let month = parts[0];
        if (month.length > 3) {
          month = month.substring(0, 3);
        }
        return `${month} ${parts[parts.length - 1]}`;
      }
      return this.monthLabel;
    }
  },
  methods: {
    setViewMode(mode) {
      this.$emit('set-view-mode', mode);
      this.$emit('update:viewDropdownOpen', false);
    },
    toggleDropdown() {
      this.$emit('update:viewDropdownOpen', !this.viewDropdownOpen);
    },
  },
};
</script>

<template>
  <div class="agenda-header">
    <!-- LEFT: View Toggles (Abas) -->
    <div class="header-left">
      <!-- Desktop: view toggles -->
      <div class="view-toggles view-toggles--desktop">
        <button
          type="button"
          class="view-btn"
          :class="{ active: viewMode === 'month' }"
          @click="setViewMode('month')"
        >
          {{ $t('AGENDA.HEADER.MONTH') }}
        </button>
        <button
          type="button"
          class="view-btn"
          :class="{ active: viewMode === 'week' }"
          @click="setViewMode('week')"
        >
          {{ $t('AGENDA.HEADER.WEEK') }}
        </button>
        <button
          type="button"
          class="view-btn"
          :class="{ active: viewMode === 'day' }"
          @click="setViewMode('day')"
        >
          {{ $t('AGENDA.HEADER.DAY') }}
        </button>
      </div>

      <!-- Mobile dropdown -->
      <div class="view-dropdown view-dropdown--mobile">
        <button
          type="button"
          class="view-dropdown-trigger"
          @click="toggleDropdown"
        >
          <span>{{
            viewMode === 'month'
              ? $t('AGENDA.HEADER.MONTH')
              : viewMode === 'week'
                ? $t('AGENDA.HEADER.WEEK')
                : $t('AGENDA.HEADER.DAY')
          }}</span>
          <i
            class="i-lucide-chevron-down view-dropdown-arrow"
            :class="{ 'rotate-180': viewDropdownOpen }"
          />
        </button>
        <div v-if="viewDropdownOpen" class="view-dropdown-menu">
          <button
            type="button"
            class="view-dropdown-item"
            :class="{ active: viewMode === 'month' }"
            @click="setViewMode('month')"
          >
            <i class="i-lucide-calendar" />
            {{ $t('AGENDA.HEADER.MONTH') }}
          </button>
          <button
            type="button"
            class="view-dropdown-item"
            :class="{ active: viewMode === 'week' }"
            @click="setViewMode('week')"
          >
            <i class="i-lucide-calendar-days" />
            {{ $t('AGENDA.HEADER.WEEK') }}
          </button>
          <button
            type="button"
            class="view-dropdown-item"
            :class="{ active: viewMode === 'day' }"
            @click="setViewMode('day')"
          >
            <i class="i-lucide-calendar-check" />
            {{ $t('AGENDA.HEADER.DAY') }}
          </button>
        </div>
      </div>

      <!-- Navigation (Arrows + Month + Today) lado a lado das abas -->
      <div class="nav-controls">
        <button class="nav-arrow group" @click="$emit('prev')">
          <i class="i-lucide-chevron-left w-4 h-4 transition-transform duration-200 group-hover:scale-[1.3]" />
        </button>
        <span class="month-label">
          <span class="hide-mobile">{{ monthLabel }}</span>
          <span class="mobile-only">{{ shortMonthLabel }}</span>
        </span>
        <button class="nav-arrow group" @click="$emit('next')">
          <i class="i-lucide-chevron-right w-4 h-4 transition-transform duration-200 group-hover:scale-[1.3]" />
        </button>
        <button class="today-btn" @click="$emit('today')">
          {{ $t('AGENDA.HEADER.TODAY') }}
        </button>
      </div>
    </div>

    <!-- RIGHT: Actions (Filters, Summary, Refresh, New Event) -->
    <div class="header-right header-actions">
      <button
        class="filter-agents-btn mobile-sidebar-toggle"
        :class="{ 'filter-agents-btn--active': showMobileSidebar }"
        @click="$emit('toggle-sidebar')"
      >
        <i class="i-lucide-filter" />
        <span class="hide-mobile">Filtros</span>
      </button>
      <button
        v-if="showSummaryBar"
        class="filter-agents-refresh-btn"
        @click="$emit('refresh-summary')"
        title="Atualizar resumo"
      >
        <i class="i-ph-arrows-clockwise" />
      </button>
      <button
        class="filter-agents-btn"
        :class="{ 'filter-agents-btn--active': showSummaryBar }"
        @click="$emit('toggle-summary')"
      >
        <i class="i-ph-chart-bar" />
        <span class="hide-mobile">Resumo</span>
      </button>
      <button v-if="canCreate" class="new-event-btn desktop-new-event" @click="$emit('new-event')">
        <i class="i-lucide-plus" />
        <span class="new-event-text">{{ $t('AGENDA.HEADER.NEW_EVENT') }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.agenda-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 16px;
  border-bottom: 1px solid rgb(var(--border-strong));
  background: rgb(var(--surface-1));
  flex-shrink: 0;
  gap: 12px;
  flex-wrap: wrap;
  position: relative;
  z-index: 50;
}

.header-left {
  display: flex;
  align-items: center;
  flex: 1;
  gap: 16px;
}

.header-right {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  flex: 1;
}

.view-toggles {
  display: flex;
  background: rgb(var(--slate-3));
  border-radius: 0.75rem;
  overflow: hidden;
}

.view-btn {
  padding: 5px 14px;
  border: none;
  background: transparent;
  color: rgb(var(--slate-11));
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s;
}

.view-btn.active {
  background: rgb(var(--blue-9));
  color: #fff;
}

.view-btn:hover:not(.active) {
  background: rgb(var(--slate-4));
}

.nav-controls {
  display: flex;
  align-items: center;
  gap: 6px;
}

.nav-arrow {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border: none;
  border-radius: 0.75rem;
  background: transparent;
  padding: 0;
  color: rgb(var(--slate-11));
  cursor: pointer;
  transition: background 0.15s;
}

.nav-arrow:hover {
  background: rgb(var(--slate-4));
}

.month-label {
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  min-width: 190px;
  text-align: center;
}

.today-btn {
  padding: 5px 14px;
  border: 1px solid rgb(var(--border-strong));
  border-radius: 0.75rem;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.15s;
  margin-left: 8px;
}

.today-btn:hover {
  background: rgb(var(--slate-4));
}

.text-period-label {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-11));
  padding: 0 8px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.filter-agents-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 16px;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 0.75rem;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-9));
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s;
}

.filter-agents-btn i {
  width: 16px;
  height: 16px;
}

.filter-agents-refresh-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  padding: 0;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 0.75rem;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-9));
  cursor: pointer;
  transition: all 0.15s;
  flex-shrink: 0;
}
.filter-agents-refresh-btn i {
  width: 16px;
  height: 16px;
}
.filter-agents-refresh-btn:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-5));
  color: rgb(var(--slate-12));
}

.filter-agents-btn:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-7));
}

.filter-agents-btn--active {
  background: rgba(59, 130, 246, 0.08);
  border-color: rgba(59, 130, 246, 0.35);
  color: #2563eb;
}

.filter-agents-btn--active:hover {
  background: rgba(59, 130, 246, 0.12);
}

.new-event-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 18px;
  border: none;
  border-radius: 0.75rem;
  background: rgb(var(--blue-9));
  color: #fff;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
}

.new-event-btn i {
  width: 16px;
  height: 16px;
}

.new-event-btn:hover {
  background: rgb(var(--blue-10));
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(var(--blue-9), 0.3);
}

/* Mobile modifiers */
.mobile-only {
  display: none;
}

.mobile-sidebar-toggle {
  display: none !important;
}

.hide-mobile {
  display: inline;
}

/* Mobile dropdown — hidden on desktop */
.view-dropdown--mobile {
  display: none;
}

/* View dropdown component */
.view-dropdown {
  position: relative;
}

.view-dropdown-trigger {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  border: 1px solid rgb(var(--border-strong));
  border-radius: 0.75rem;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s;
  white-space: nowrap;
}

.view-dropdown-trigger:hover {
  background: rgb(var(--slate-4));
}

.view-dropdown-arrow {
  width: 14px;
  height: 14px;
  transition: transform 0.2s;
}

.view-dropdown-arrow.rotate-180 {
  transform: rotate(180deg);
}

.view-dropdown-menu {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  min-width: 160px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--border-strong));
  border-radius: 0.75rem;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
  z-index: 200;
  overflow: hidden;
  padding: 4px;
  animation: dropIn 0.12s ease-out;
}

@keyframes dropIn {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.view-dropdown-item {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 10px 14px;
  border: none;
  border-radius: 0.75rem;
  background: transparent;
  color: rgb(var(--slate-11));
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.12s;
}

.view-dropdown-item i {
  width: 16px;
  height: 16px;
}

.view-dropdown-item:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.view-dropdown-item.active {
  background: rgba(59, 130, 246, 0.1);
  color: rgb(var(--blue-9));
  font-weight: 600;
}

@media (max-width: 767px) {
  .hide-mobile {
    display: none !important;
  }

  .mobile-only {
    display: inline !important;
  }

  .agenda-header {
    flex-direction: row;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 4px;
    padding: 6px 8px;
    overflow: visible;
  }

  .header-left {
    flex: 1 1 auto;
    order: -1;
    justify-content: flex-start;
    flex-wrap: nowrap;
    gap: 4px;
    margin-bottom: 0px;
    min-width: 0;
  }

  .filter-agents-btn {
    width: 34px;
    height: 34px;
    padding: 0;
    justify-content: center;
  }

  .filter-agents-btn i {
    margin: 0;
  }
  .header-right {
    flex: 0 0 auto;
    justify-content: flex-end;
  }

  .month-label {
    min-width: auto;
    @apply text-sm;
    flex: 0 0 auto;
  }

  .nav-arrow {
    width: 28px;
    height: 28px;
  }

  .view-toggles--desktop {
    display: none !important;
  }

  .view-dropdown--mobile {
    display: block;
  }

  .desktop-new-event {
    display: none !important;
  }

  .mobile-sidebar-toggle {
    display: flex !important;
  }
}

@media (min-width: 768px) and (max-width: 1023px) {
  .mobile-sidebar-toggle {
    display: flex !important;
  }

  .month-label {
    min-width: 140px;
    @apply text-sm;
  }
}

@media (min-width: 1024px) and (max-width: 1279px) {
  .mobile-sidebar-toggle {
    display: flex !important;
  }
}
</style>
