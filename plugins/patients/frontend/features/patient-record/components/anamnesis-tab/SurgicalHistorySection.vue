<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  anamnesis: { type: Object, required: true },
});

const { t } = useI18n();

const isFinalized = computed(() => props.anamnesis.status === 'finalized');

const CHECKBOXES = [
  {
    key: 'has_recent_surgeries',
    labelKey: 'PATIENT_ANAMNESIS.SECTIONS.SURGICAL.RECENT_SURGERIES',
  },
  {
    key: 'has_implants',
    labelKey: 'PATIENT_ANAMNESIS.SECTIONS.SURGICAL.IMPLANTS',
  },
  {
    key: 'has_anesthesia_complications',
    labelKey: 'PATIENT_ANAMNESIS.SECTIONS.SURGICAL.ANESTHESIA',
  },
];
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-orange">
          <i class="i-lucide-scissors w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.SURGICAL.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.SURGICAL.SUBTITLE') }}
          </span>
        </div>
      </div>
    </div>
    <div class="reg-section-body">
      <div class="anm-check-col">
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
          {{ t('PATIENT_ANAMNESIS.SECTIONS.SURGICAL.DETAILS_LABEL') }}
        </label>
        <textarea
          v-model="anamnesis.surgical_history"
          class="form-input form-textarea"
          rows="2"
          :placeholder="
            t('PATIENT_ANAMNESIS.SECTIONS.SURGICAL.DETAILS_PLACEHOLDER')
          "
          :disabled="isFinalized"
        />
      </div>
    </div>
  </div>
</template>
