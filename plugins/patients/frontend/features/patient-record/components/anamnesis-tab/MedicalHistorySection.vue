<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  anamnesis: { type: Object, required: true },
});

const { t } = useI18n();

const isFinalized = computed(() => props.anamnesis.status === 'finalized');

const CHECKBOXES = [
  { key: 'hypertension', labelKey: 'PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.HYPERTENSION' },
  { key: 'pregnant', labelKey: 'PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.PREGNANT' },
  { key: 'diabetes', labelKey: 'PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.DIABETES' },
  { key: 'oncology', labelKey: 'PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.ONCOLOGY' },
  { key: 'bleeding_disorder', labelKey: 'PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.BLEEDING' },
  { key: 'hepatitis', labelKey: 'PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.HEPATITIS' },
];
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-blue">
          <i class="i-lucide-activity w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.SUBTITLE') }}
          </span>
        </div>
      </div>
    </div>
    <div class="reg-section-body">
      <div class="anm-check-grid">
        <label v-for="cb in CHECKBOXES" :key="cb.key" class="check-item">
          <input
            v-model="anamnesis.medical_history[cb.key]"
            type="checkbox"
            :disabled="isFinalized"
          />
          <div class="check-item-box" />
          <span class="check-item-label">{{ t(cb.labelKey) }}</span>
        </label>
      </div>
      <div class="form-group">
        <label class="form-label">
          {{ t('PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.OTHER_LABEL') }}
        </label>
        <input
          v-model="anamnesis.medical_history.other"
          type="text"
          class="form-input"
          :placeholder="
            t('PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.OTHER_PLACEHOLDER')
          "
          :disabled="isFinalized"
        />
      </div>
    </div>
  </div>
</template>
