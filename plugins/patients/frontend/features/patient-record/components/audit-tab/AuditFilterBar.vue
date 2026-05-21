<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  filters: { type: Object, required: true },
});

const emit = defineEmits(['update:filters', 'apply', 'clear']);

const { t } = useI18n();

const hasActiveFilters = computed(
  () =>
    !!(
      props.filters.action_type ||
      props.filters.actor_id ||
      props.filters.start_date ||
      props.filters.end_date
    )
);

const ACTION_OPTIONS = computed(() => [
  { value: '', label: t('PATIENT_AUDIT.FILTERS.ALL_ACTIONS') },
  { value: 'view', label: t('PATIENT_AUDIT.ACTION_OPTIONS.VIEW') },
  { value: 'create', label: t('PATIENT_AUDIT.ACTION_OPTIONS.CREATE') },
  { value: 'update', label: t('PATIENT_AUDIT.ACTION_OPTIONS.UPDATE') },
  { value: 'delete', label: t('PATIENT_AUDIT.ACTION_OPTIONS.DELETE') },
  { value: 'sign', label: t('PATIENT_AUDIT.ACTION_OPTIONS.SIGN') },
  { value: 'export', label: t('PATIENT_AUDIT.ACTION_OPTIONS.EXPORT') },
  { value: 'finalize', label: t('PATIENT_AUDIT.ACTION_OPTIONS.FINALIZE') },
  { value: 'approve', label: t('PATIENT_AUDIT.ACTION_OPTIONS.APPROVE') },
  { value: 'pay', label: t('PATIENT_AUDIT.ACTION_OPTIONS.PAY') },
  { value: 'print', label: t('PATIENT_AUDIT.ACTION_OPTIONS.PRINT') },
  {
    value: 'clinical_override',
    label: t('PATIENT_AUDIT.ACTION_OPTIONS.CLINICAL_OVERRIDE'),
  },
]);

const updateField = (field, value) => {
  emit('update:filters', { ...props.filters, [field]: value });
};
</script>

<template>
  <div class="aud-filter-bar mb-5">
    <div class="aud-filter-field">
      <label class="aud-filter-label">
        {{ t('PATIENT_AUDIT.FILTERS.ACTION_LABEL') }}
      </label>
      <FormSelect
        :model-value="filters.action_type"
        :options="ACTION_OPTIONS"
        :placeholder="t('PATIENT_AUDIT.FILTERS.ACTION_PLACEHOLDER')"
        auto-searchable
        @update:model-value="updateField('action_type', $event)"
      />
    </div>
    <div class="aud-filter-field">
      <label class="aud-filter-label">
        {{ t('PATIENT_AUDIT.FILTERS.DATE_FROM') }}
      </label>
      <DatePickerBR
        :model-value="filters.start_date"
        :placeholder="t('PATIENT_AUDIT.FILTERS.DATE_PLACEHOLDER')"
        :max="filters.end_date || undefined"
        @update:model-value="updateField('start_date', $event)"
      />
    </div>
    <div class="aud-filter-field">
      <label class="aud-filter-label">
        {{ t('PATIENT_AUDIT.FILTERS.DATE_TO') }}
      </label>
      <DatePickerBR
        :model-value="filters.end_date"
        :placeholder="t('PATIENT_AUDIT.FILTERS.DATE_PLACEHOLDER')"
        :min="filters.start_date || undefined"
        @update:model-value="updateField('end_date', $event)"
      />
    </div>
    <div class="aud-filter-actions">
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-filter"
        :label="t('PATIENT_AUDIT.FILTERS.APPLY')"
        @click="emit('apply')"
      />
      <BeclinicButton
        v-if="hasActiveFilters"
        variant="ghost"
        color="slate"
        icon="i-lucide-x"
        :title="t('PATIENT_AUDIT.FILTERS.CLEAR_TITLE')"
        @click="emit('clear')"
      />
    </div>
  </div>
</template>
