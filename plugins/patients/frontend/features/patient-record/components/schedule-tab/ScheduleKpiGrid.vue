<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  kpis: {
    type: Object,
    default: () => ({ total: 0, done: 0, upcoming: 0, noShows: 0 }),
  },
});

const { t } = useI18n();
</script>

<template>
  <div class="sched-kpi-grid mb-6">
    <div class="sched-kpi-card">
      <div class="sched-kpi-icon">
        <i class="i-lucide-calendar-days w-4 h-4" />
      </div>
      <p class="sched-kpi-label">{{ t('PATIENT_SCHEDULE.KPI.TOTAL') }}</p>
      <p class="sched-kpi-value">{{ kpis.total }}</p>
    </div>
    <div class="sched-kpi-card sched-kpi-card--green">
      <div class="sched-kpi-icon sched-kpi-icon--green">
        <i class="i-lucide-check-circle-2 w-4 h-4" />
      </div>
      <p class="sched-kpi-label">{{ t('PATIENT_SCHEDULE.KPI.DONE') }}</p>
      <p class="sched-kpi-value">{{ kpis.done }}</p>
    </div>
    <div class="sched-kpi-card sched-kpi-card--blue">
      <div class="sched-kpi-icon sched-kpi-icon--blue">
        <i class="i-lucide-clock w-4 h-4" />
      </div>
      <p class="sched-kpi-label">{{ t('PATIENT_SCHEDULE.KPI.UPCOMING') }}</p>
      <p class="sched-kpi-value">{{ kpis.upcoming }}</p>
    </div>
    <div class="sched-kpi-card sched-kpi-card--red">
      <div class="sched-kpi-icon sched-kpi-icon--red">
        <i class="i-lucide-user-x w-4 h-4" />
      </div>
      <p class="sched-kpi-label">{{ t('PATIENT_SCHEDULE.KPI.NO_SHOWS') }}</p>
      <p class="sched-kpi-value">{{ kpis.noShows }}</p>
    </div>
  </div>
</template>
