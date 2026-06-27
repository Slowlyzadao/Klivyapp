<script setup>
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';

defineProps({
  summary: { type: Object, default: null },
});

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';
</script>

<template>
  <div class="fin-kpi-grid mb-5">
    <div class="fin-kpi-card">
      <div class="fin-kpi-icon">
        <i class="i-lucide-trending-up w-3.5 h-3.5" />
      </div>
      <p class="fin-kpi-label">{{ t('PATIENT_FINANCIAL.KPI.TOTAL_APPROVED') }}</p>
      <p class="fin-kpi-value">{{ formatCurrency(summary?.total_approved) }}</p>
      <p class="fin-kpi-hint">{{ t('PATIENT_FINANCIAL.KPI.TOTAL_APPROVED_HINT') }}</p>
    </div>

    <div class="fin-kpi-card fin-kpi-card--green">
      <div class="fin-kpi-icon fin-kpi-icon--green">
        <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
      </div>
      <p class="fin-kpi-label">{{ t('PATIENT_FINANCIAL.KPI.TOTAL_PAID') }}</p>
      <p class="fin-kpi-value">{{ formatCurrency(summary?.total_paid) }}</p>
      <p class="fin-kpi-hint">{{ t('PATIENT_FINANCIAL.KPI.TOTAL_PAID_HINT') }}</p>
    </div>

    <div class="fin-kpi-card fin-kpi-card--amber">
      <div class="fin-kpi-icon fin-kpi-icon--amber">
        <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
      </div>
      <p class="fin-kpi-label">{{ t('PATIENT_FINANCIAL.KPI.TOTAL_OPEN') }}</p>
      <p class="fin-kpi-value">{{ formatCurrency(summary?.total_open) }}</p>
      <p class="fin-kpi-hint">
        {{
          summary?.next_due_date
            ? t('PATIENT_FINANCIAL.KPI.NEXT_DUE', { date: formatDate(summary.next_due_date) })
            : t('PATIENT_FINANCIAL.KPI.NO_PENDING')
        }}
      </p>
    </div>

    <div class="fin-kpi-card fin-kpi-card--red">
      <div class="fin-kpi-icon fin-kpi-icon--red">
        <i class="i-lucide-alert-circle w-3.5 h-3.5" />
      </div>
      <p class="fin-kpi-label">{{ t('PATIENT_FINANCIAL.KPI.TOTAL_OVERDUE') }}</p>
      <p
        class="fin-kpi-value"
        :class="{ 'fin-kpi-value--danger': summary?.total_overdue > 0 }"
      >
        {{ formatCurrency(summary?.total_overdue) }}
      </p>
      <p class="fin-kpi-hint">
        {{
          summary?.total_overdue > 0
            ? t('PATIENT_FINANCIAL.KPI.OVERDUE_NEEDS_ATTENTION')
            : t('PATIENT_FINANCIAL.KPI.OVERDUE_ALL_OK')
        }}
      </p>
    </div>

    <div class="fin-kpi-card fin-kpi-card--blue">
      <div class="fin-kpi-icon fin-kpi-icon--blue">
        <i class="i-lucide-wallet w-3.5 h-3.5" />
      </div>
      <p class="fin-kpi-label">{{ t('PATIENT_FINANCIAL.KPI.CREDIT') }}</p>
      <p class="fin-kpi-value">{{ formatCurrency(summary?.credit_balance) }}</p>
      <p class="fin-kpi-hint">{{ t('PATIENT_FINANCIAL.KPI.CREDIT_HINT') }}</p>
    </div>
  </div>
</template>
