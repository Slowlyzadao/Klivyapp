<script setup>
/**
 * AnamnesisTab — Aba "Anamnese / Questionário Clínico" do prontuário.
 *
 * Orquestrador. Composição:
 *   • useAnamnesis — fetch + save + finalize + dirty tracking
 *   • anamnesis-tab/* (6 sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota. Dirty tracking bloqueia navegação
 * SPA (onBeforeRouteLeave) e fecha de aba (beforeunload) para evitar perda
 * de edição clínica não salva.
 */
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, onBeforeRouteLeave } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAnamnesis } from '@plugins/patients/frontend/features/patient-record/composables/useAnamnesis';
import AnamnesisHeader from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/AnamnesisHeader.vue';
import ChiefComplaintSection from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/ChiefComplaintSection.vue';
import MedicalHistorySection from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/MedicalHistorySection.vue';
import AllergiesMedicationsSection from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/AllergiesMedicationsSection.vue';
import SurgicalHistorySection from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/SurgicalHistorySection.vue';
import HabitsSection from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/HabitsSection.vue';
import AnamnesisHistoryModal from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/AnamnesisHistoryModal.vue';
import ClinicSpecialtiesModal from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/ClinicSpecialtiesModal.vue';
import AnamnesisReadonlyView from '@plugins/patients/frontend/features/patient-record/components/anamnesis-tab/AnamnesisReadonlyView.vue';

const { t } = useI18n();
const route = useRoute();
const patientId = computed(() => route.params.patientId);

const {
  anamneses,
  currentAnamnesis,
  allergyInput,
  medicationInput,
  isSaving,
  isDirty,
  fetch: fetchAnamneses,
  saveAnamnesis,
  startNew,
  flushAllergyInput,
  flushMedicationInput,
  removeAllergy,
  removeMedication,
} = useAnamnesis(patientId);

const showHistoryModal = ref(false);
const showClinicSettingsModal = ref(false);

// Quando assinada, troca o form pelo layout de "documento" — UX de leitura
// em vez de form com inputs disabled (apagados/quebrados).
const isFinalized = computed(
  () => currentAnamnesis.value.status === 'finalized'
);

const openPdf = () => {
  const url = currentAnamnesis.value.pdf_url;
  if (url) window.open(url, '_blank', 'noopener,noreferrer');
};

const openHistoryItemPdf = item => {
  if (item?.pdf_url) window.open(item.pdf_url, '_blank', 'noopener,noreferrer');
};

// Guard contra fechar aba/refresh com edição não salva. Browsers só exibem
// prompt nativo — é o máximo que dá no nível do user agent.
const beforeUnloadHandler = e => {
  if (!isDirty.value) return;
  e.preventDefault();
  e.returnValue = '';
};

onBeforeRouteLeave(() => {
  if (!isDirty.value) return true;
  // eslint-disable-next-line no-alert
  return window.confirm(t('PATIENT_ANAMNESIS.MESSAGES.DIRTY_LEAVE_CONFIRM'));
});

onMounted(() => {
  fetchAnamneses();
  window.addEventListener('beforeunload', beforeUnloadHandler);
});

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', beforeUnloadHandler);
});
</script>

<template>
  <div class="tab-pane fade-in">
    <AnamnesisHeader
      :anamnesis="currentAnamnesis"
      :anamneses="anamneses"
      :is-dirty="isDirty"
      :is-saving="isSaving"
      @view-pdf="openPdf"
      @start-new="startNew"
      @save="saveAnamnesis(false)"
      @finalize="saveAnamnesis(true)"
      @open-history="showHistoryModal = true"
      @open-clinic-settings="showClinicSettingsModal = true"
    />

    <AnamnesisReadonlyView
      v-if="isFinalized"
      :anamnesis="currentAnamnesis"
    />

    <div v-else class="reg-form-grid">
      <ChiefComplaintSection :anamnesis="currentAnamnesis" />

      <MedicalHistorySection :anamnesis="currentAnamnesis" />

      <AllergiesMedicationsSection
        :anamnesis="currentAnamnesis"
        :allergy-input="allergyInput"
        :medication-input="medicationInput"
        @update:allergy-input="allergyInput = $event"
        @update:medication-input="medicationInput = $event"
        @flush-allergy="flushAllergyInput"
        @flush-medication="flushMedicationInput"
        @remove-allergy="removeAllergy"
        @remove-medication="removeMedication"
      />

      <SurgicalHistorySection :anamnesis="currentAnamnesis" />

      <HabitsSection :anamnesis="currentAnamnesis" />
    </div>

    <AnamnesisHistoryModal
      :open="showHistoryModal"
      :anamneses="anamneses"
      @close="showHistoryModal = false"
      @view-pdf="openHistoryItemPdf"
    />

    <ClinicSpecialtiesModal
      :open="showClinicSettingsModal"
      @close="showClinicSettingsModal = false"
    />
  </div>
</template>
