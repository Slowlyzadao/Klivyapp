<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import { useClinicProfile } from '@plugins/beclinic_core/frontend/composables/useClinicProfile';
import { SPECIALTY_OPTIONS } from '@plugins/patients/frontend/constants/anamnesis';

const props = defineProps({
  anamnesis: { type: Object, required: true },
});

const { t } = useI18n();
const { profile: clinicProfile } = useClinicProfile();

// Se a clínica configurou `enabled_specialties`, filtramos as opções por
// elas. Caso a anamnese atual já tenha um valor que não está mais na lista
// (ex.: especialidade desabilitada depois), mantemos a opção visível pra
// não quebrar o select — é histórico legítimo.
const filteredSpecialtyOptions = computed(() => {
  const enabled = clinicProfile.value?.enabled_specialties || [];
  if (enabled.length === 0) return SPECIALTY_OPTIONS;
  const filtered = SPECIALTY_OPTIONS.filter(opt => enabled.includes(opt.value));
  enabled.forEach(label => {
    if (!filtered.some(opt => opt.value === label)) {
      filtered.push({ value: label, label });
    }
  });
  const current = props.anamnesis?.specialty;
  if (current && !filtered.some(opt => opt.value === current)) {
    filtered.push({ value: current, label: current });
  }
  return filtered;
});
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-cyan">
          <i class="i-lucide-stethoscope w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.SUBTITLE') }}
          </span>
        </div>
      </div>
    </div>
    <div class="reg-section-body">
      <div class="reg-field-grid-2">
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.SPECIALTY_LABEL') }}
          </label>
          <FormSelect
            v-model="anamnesis.specialty"
            :options="filteredSpecialtyOptions"
            :disabled="anamnesis.status === 'finalized'"
            :placeholder="
              t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.SPECIALTY_PLACEHOLDER')
            "
          />
        </div>
      </div>
      <div class="form-group">
        <label class="form-label">
          {{ t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.COMPLAINT_LABEL') }}
          <span class="reg-required">*</span>
        </label>
        <textarea
          v-model="anamnesis.chief_complaint"
          class="form-input form-textarea"
          rows="3"
          :placeholder="
            t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.COMPLAINT_PLACEHOLDER')
          "
          :disabled="anamnesis.status === 'finalized'"
        />
      </div>
    </div>
  </div>
</template>
