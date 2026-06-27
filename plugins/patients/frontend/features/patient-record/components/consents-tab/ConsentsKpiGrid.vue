<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  stats: {
    type: Object,
    default: () => ({ total: 0, signed: 0, pending: 0, expired: 0 }),
  },
});

const { t } = useI18n();
</script>

<template>
  <div class="consent-kpi-grid mb-5">
    <div class="consent-kpi-card">
      <div class="consent-kpi-icon consent-kpi-icon--neutral">
        <i class="i-lucide-files w-4 h-4" />
      </div>
      <div>
        <p class="consent-kpi-label">{{ t('PATIENT_CONSENTS.KPI.TOTAL') }}</p>
        <p class="consent-kpi-value">{{ stats.total }}</p>
      </div>
    </div>
    <div class="consent-kpi-card consent-kpi-card--green">
      <div class="consent-kpi-icon consent-kpi-icon--green">
        <i class="i-lucide-check-circle w-4 h-4" />
      </div>
      <div>
        <p class="consent-kpi-label consent-kpi-label--green">
          {{ t('PATIENT_CONSENTS.KPI.SIGNED') }}
        </p>
        <p class="consent-kpi-value consent-kpi-value--green">
          {{ stats.signed }}
        </p>
      </div>
    </div>
    <div class="consent-kpi-card consent-kpi-card--amber">
      <div class="consent-kpi-icon consent-kpi-icon--amber">
        <i class="i-lucide-clock w-4 h-4" />
      </div>
      <div>
        <p class="consent-kpi-label consent-kpi-label--amber">
          {{ t('PATIENT_CONSENTS.KPI.PENDING') }}
        </p>
        <p class="consent-kpi-value consent-kpi-value--amber">
          {{ stats.pending }}
        </p>
      </div>
    </div>
    <div class="consent-kpi-card consent-kpi-card--red">
      <div class="consent-kpi-icon consent-kpi-icon--red">
        <i class="i-lucide-alert-triangle w-4 h-4" />
      </div>
      <div>
        <p class="consent-kpi-label consent-kpi-label--red">
          {{ t('PATIENT_CONSENTS.KPI.EXPIRED') }}
        </p>
        <p class="consent-kpi-value consent-kpi-value--red">
          {{ stats.expired }}
        </p>
      </div>
    </div>
  </div>
</template>
