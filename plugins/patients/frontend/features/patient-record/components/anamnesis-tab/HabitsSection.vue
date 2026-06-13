<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import {
  SMOKER_OPTIONS,
  ALCOHOL_OPTIONS,
  SPORTS_OPTIONS,
} from '@plugins/patients/frontend/constants/anamnesis';

const props = defineProps({
  anamnesis: { type: Object, required: true },
});

const { t } = useI18n();

const isFinalized = computed(() => props.anamnesis.status === 'finalized');
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-green">
          <i class="i-lucide-leaf w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SUBTITLE') }}
          </span>
        </div>
      </div>
    </div>
    <div class="reg-section-body">
      <div class="reg-field-grid-3">
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SMOKER_LABEL') }}
          </label>
          <FormSelect
            v-model="anamnesis.relevant_habits.smoker"
            :options="SMOKER_OPTIONS"
            :disabled="isFinalized"
            :placeholder="t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SELECT_PLACEHOLDER')"
          />
        </div>
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.ALCOHOL_LABEL') }}
          </label>
          <FormSelect
            v-model="anamnesis.relevant_habits.alcohol"
            :options="ALCOHOL_OPTIONS"
            :disabled="isFinalized"
            :placeholder="t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SELECT_PLACEHOLDER')"
          />
        </div>
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SPORTS_LABEL') }}
          </label>
          <FormSelect
            v-model="anamnesis.relevant_habits.sports"
            :options="SPORTS_OPTIONS"
            :disabled="isFinalized"
            :placeholder="t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SELECT_PLACEHOLDER')"
          />
        </div>
      </div>
      <div class="anm-notes-card">
        <div class="flex items-center gap-2 mb-3">
          <i class="i-lucide-shield-alert w-4 h-4 anm-notes-header-icon" />
          <span
            class="anm-notes-header-label text-xs font-semibold uppercase tracking-wider"
          >
            {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.NOTES_TITLE') }}
          </span>
        </div>
        <textarea
          v-model="anamnesis.additional_notes"
          class="form-input form-textarea anm-notes-input"
          rows="3"
          :placeholder="t('PATIENT_ANAMNESIS.SECTIONS.HABITS.NOTES_PLACEHOLDER')"
          :disabled="isFinalized"
        />
      </div>
    </div>
  </div>
</template>
