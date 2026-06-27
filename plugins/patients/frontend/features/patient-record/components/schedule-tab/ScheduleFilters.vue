<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  active: { type: String, default: 'all' },
  issuesCount: { type: Number, default: 0 },
});

const emit = defineEmits(['update:active']);

const { t } = useI18n();
</script>

<template>
  <div class="sched-filter-row mb-6">
    <button
      class="sched-filter-btn"
      :class="{ 'sched-filter-btn--active': active === 'all' }"
      @click="emit('update:active', 'all')"
    >
      <i class="i-lucide-layout-grid w-3.5 h-3.5" />
      {{ t('PATIENT_SCHEDULE.FILTERS.ALL') }}
    </button>
    <button
      class="sched-filter-btn"
      :class="{ 'sched-filter-btn--active': active === 'upcoming' }"
      @click="emit('update:active', 'upcoming')"
    >
      <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
      {{ t('PATIENT_SCHEDULE.FILTERS.UPCOMING') }}
    </button>
    <button
      class="sched-filter-btn"
      :class="{ 'sched-filter-btn--active': active === 'issues' }"
      @click="emit('update:active', 'issues')"
    >
      <i class="i-lucide-octagon-alert w-3.5 h-3.5" />
      {{ t('PATIENT_SCHEDULE.FILTERS.ISSUES') }}
      <span v-if="issuesCount > 0" class="sched-filter-badge">
        {{ issuesCount }}
      </span>
    </button>
  </div>
</template>
