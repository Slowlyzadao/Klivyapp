<script setup>
/**
 * waiting-list/WaitingListSidebarSection.vue
 *
 * Seção "Lista de Espera" na sidebar da Agenda.
 * Usa as MESMAS classes CSS do AgendaDashboard (sidebar-section,
 * sidebar-collapse-btn, filter-content, agent-item, agent-name)
 * para garantir visual idêntico a PRIORIDADE/TIPO DE EVENTO/TRATAMENTOS.
 */
import { computed } from 'vue';
import { waitingListStore } from './store';

defineProps({
  expanded: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);

const PERIOD_ICONS = {
  morning: 'i-ph-sun-horizon',
  afternoon: 'i-ph-sun',
  evening: 'i-ph-moon',
};

const PERIOD_LABELS = {
  morning: 'Manhã',
  afternoon: 'Tarde',
  evening: 'Noite',
};

const DAY_LABELS = {
  mon: 'SEG',
  tue: 'TER',
  wed: 'QUA',
  thu: 'QUI',
  fri: 'SEX',
  sat: 'SAB',
  sun: 'DOM',
};

const entries = computed(() => waitingListStore.entries);

function removeEntry(id) {
  waitingListStore.remove(id);
}

function periodLabel(period) {
  return PERIOD_LABELS[period] || period;
}

function periodIcon(period) {
  return PERIOD_ICONS[period] || 'i-ph-clock';
}

function daysLabel(days) {
  if (!days || !days.length) return '';
  return days.map(d => DAY_LABELS[d] || d).join(', ');
}
</script>

<template>
  <div class="sidebar-section">
    <button class="sidebar-collapse-btn" @click="emit('toggle')">
      <span>
        {{ $t('WAITING_LIST.SIDEBAR_TITLE') }}
        <span v-if="entries.length" class="wl-count-pill">
          {{ entries.length }}
        </span>
      </span>
      <i :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" />
    </button>

    <div v-if="expanded" class="filter-content">
      <!-- Empty state -->
      <div v-if="!entries.length" class="agent-item wl-empty-item">
        <span class="i-ph-clock-countdown wl-empty-icon" />
        <span class="agent-name wl-empty-text">
          {{ $t('WAITING_LIST.SIDEBAR_EMPTY') }}
        </span>
      </div>

      <!-- Entries -->
      <div v-for="entry in entries" :key="entry.id" class="agent-item">
        <!-- Avatar/inicial -->
        <div class="wl-avatar">
          <img
            v-if="entry.contactAvatar"
            :src="entry.contactAvatar"
            :alt="entry.contactName"
            class="wl-avatar-img"
          />
          <span v-else class="wl-avatar-initial">
            {{ entry.contactName?.charAt(0)?.toUpperCase() }}
          </span>
        </div>

        <!-- Nome -->
        <span class="agent-name wl-entry-name">{{ entry.contactName }}</span>

        <!-- Período -->
        <span
          class="wl-period-icon"
          :class="periodIcon(entry.period)"
          :title="periodLabel(entry.period)"
        />

        <!-- Tooltip popover com detalhes (hover) -->
        <div class="wl-info-wrap">
          <button
            class="wl-info-btn"
            :aria-label="$t('WAITING_LIST.TOOLTIP_LABEL')"
          >
            <span class="i-ph-info" />
          </button>
          <div class="wl-tooltip" role="tooltip">
            <p class="wl-tip-row">
              <span class="i-ph-user wl-tip-icon" />
              <span>{{ entry.contactName }}</span>
            </p>
            <p class="wl-tip-row">
              <span class="wl-tip-icon" :class="periodIcon(entry.period)" />
              <span>
                {{ periodLabel(entry.period) }}
                <span v-if="entry.specificTime" class="wl-tip-muted">
                  {{ '— ' + entry.specificTime }}
                </span>
              </span>
            </p>
            <p
              v-if="entry.preferredDays && entry.preferredDays.length"
              class="wl-tip-row"
            >
              <span class="i-ph-calendar wl-tip-icon" />
              <span>{{ daysLabel(entry.preferredDays) }}</span>
            </p>
            <p v-if="entry.notes" class="wl-tip-row wl-tip-notes">
              <span class="i-ph-note wl-tip-icon" />
              <span>{{ entry.notes }}</span>
            </p>
          </div>
        </div>

        <!-- Remover -->
        <button
          class="wl-remove-btn"
          :aria-label="$t('WAITING_LIST.REMOVE_LABEL')"
          @click="removeEntry(entry.id)"
        >
          <span class="i-ph-x" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Pílula de contagem no título */
.wl-count-pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  border-radius: 99px;
  background: rgba(99, 102, 241, 0.15);
  color: #6366f1;
  font-size: 9px;
  font-weight: 700;
  margin-left: 4px;
  vertical-align: middle;
}

/* Empty state */
.wl-empty-item {
  cursor: default !important;
  opacity: 0.7;
}

.wl-empty-item:hover {
  background: transparent !important;
}

.wl-empty-icon {
  @apply text-sm;
  color: rgb(var(--slate-9));
}

.wl-empty-text {
  font-style: italic;
  color: rgb(var(--slate-9));
  @apply text-sm;
}

/* Avatar */
.wl-avatar {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: rgba(99, 102, 241, 0.15);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  overflow: hidden;
}

.wl-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.wl-avatar-initial {
  font-size: 9px;
  font-weight: 700;
  color: #6366f1;
}

/* Entry name */
.wl-entry-name {
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Período (ícone colorido) */
.wl-period-icon {
  @apply text-sm;
  color: rgb(var(--slate-9));
  flex-shrink: 0;
}

/* Info wrap + tooltip */
.wl-info-wrap {
  position: relative;
  display: flex;
  align-items: center;
}

.wl-info-wrap:hover .wl-tooltip,
.wl-info-wrap:focus-within .wl-tooltip {
  opacity: 1;
  pointer-events: auto;
  transform: translateY(0);
}

.wl-info-btn {
  width: 18px;
  height: 18px;
  border: none;
  background: transparent;
  cursor: pointer;
  color: rgb(var(--slate-8));
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-sm;
  border-radius: 4px;
  transition: color 0.12s;
}

.wl-info-btn:hover {
  color: rgb(var(--slate-12));
}

.wl-tooltip {
  position: absolute;
  right: 0;
  top: calc(100% + 6px);
  z-index: 9999;
  min-width: 180px;
  max-width: 230px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 5px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
  opacity: 0;
  pointer-events: none;
  transform: translateY(-4px);
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
}

.wl-tip-row {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  @apply text-sm;
  color: rgb(var(--slate-11));
  margin: 0;
  line-height: 1.4;
}

.wl-tip-icon {
  @apply text-sm;
  color: rgb(var(--slate-9));
  flex-shrink: 0;
  margin-top: 1px;
}

.wl-tip-muted {
  color: rgb(var(--slate-9));
}

.wl-tip-notes {
  font-style: italic;
  color: rgb(var(--slate-9));
}

/* Remover */
.wl-remove-btn {
  width: 16px;
  height: 16px;
  border: none;
  background: transparent;
  cursor: pointer;
  color: rgb(var(--slate-7));
  display: flex;
  align-items: center;
  justify-content: center;
  @apply text-sm;
  border-radius: 3px;
  opacity: 0;
  transition:
    opacity 0.12s,
    color 0.12s;
}

.agent-item:hover .wl-remove-btn {
  opacity: 1;
}

.wl-remove-btn:hover {
  color: #dc2626;
}
</style>
