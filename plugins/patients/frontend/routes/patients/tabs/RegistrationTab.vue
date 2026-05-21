<script setup>
/**
 * RegistrationTab — Aba "Cadastro" do prontuário do paciente.
 *
 * Orquestrador. Composição:
 *   • useRegistrationActions — saveRegistration + updateAvatar
 *   • useCameraCapture (interno em CameraCaptureModal)
 *   • usePhoneContactSearch — busca paralela paciente+chat
 *   • useCepLookup — autosearch ViaCEP com flag de dirty
 *   • registration-tab/* (8 sub-componentes)
 *
 * Patient passado por referência (mutações em campos aninhados via v-model
 * propagam pro pai). Emite `saved` após persistir — pai re-fetcha pra
 * recalcular Age, status, tags clínicas.
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { processImageToWebP } from '@plugins/patients/frontend/features/patient-record/composables/useCameraCapture';
import { useRegistrationActions } from '@plugins/patients/frontend/features/patient-record/composables/useRegistrationActions';
import { usePhoneContactSearch } from '@plugins/patients/frontend/features/patient-record/composables/usePhoneContactSearch';
import { useCepLookup } from '@plugins/patients/frontend/features/patient-record/composables/useCepLookup';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import {
  formatPhoneDisplay,
  maskPhone,
} from '@plugins/patients/frontend/features/patient-record/utils/registrationMasks';
import RegistrationHeader from '@plugins/patients/frontend/features/patient-record/components/registration-tab/RegistrationHeader.vue';
import RegistrationPersonalSection from '@plugins/patients/frontend/features/patient-record/components/registration-tab/RegistrationPersonalSection.vue';
import RegistrationContactSection from '@plugins/patients/frontend/features/patient-record/components/registration-tab/RegistrationContactSection.vue';
import RegistrationAddressSection from '@plugins/patients/frontend/features/patient-record/components/registration-tab/RegistrationAddressSection.vue';
import RegistrationAdminSection from '@plugins/patients/frontend/features/patient-record/components/registration-tab/RegistrationAdminSection.vue';
import CameraCaptureModal from '@plugins/patients/frontend/features/patient-record/components/registration-tab/CameraCaptureModal.vue';

const props = defineProps({
  patient: { type: Object, required: true },
});
const emit = defineEmits(['saved']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const patientId = computed(() => route.params.patientId);

// ── Composables ─────────────────────────────────────────────────
const { isLoading, updateAvatar, saveRegistration } = useRegistrationActions(
  patientId,
  { onSaved: () => emit('saved') }
);

const {
  phoneContactResults,
  phonePatientResults,
  phoneContactSearching,
  phoneContactDropdown,
  search: searchPhone,
  reset: resetPhoneSearch,
  skipNext: skipNextPhoneSearch,
} = usePhoneContactSearch({ excludeId: () => props.patient?.id });

const { cepUserDirty, markCepDirty, searchCep } = useCepLookup();

// ── Local state ────────────────────────────────────────────────
const regSections = ref({
  personal: true,
  contact: true,
  address: false,
  admin: false,
});

const editFirstName = ref('');
const editLastName = ref('');
const showCameraModal = ref(false);

// Sync first/last name from patient.name
const initEditNameFromPatient = () => {
  const parts = (props.patient?.name || '').trim().split(' ');
  editFirstName.value = parts[0] || '';
  editLastName.value = parts.slice(1).join(' ') || '';
};

watch(() => props.patient?.name, () => initEditNameFromPatient(), {
  immediate: true,
});

// ── Avatar / Câmera ────────────────────────────────────────────
const handleAvatarFile = async file => {
  try {
    const processed = await processImageToWebP(file, 300);
    await updateAvatar(processed, props.patient);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[Registration] processImageToWebP falhou', error);
    useNotification.error(t('PATIENT_REGISTRATION.MESSAGES.AVATAR_ERROR'));
  }
};

const handleCameraPhoto = async file => {
  const { ok } = await updateAvatar(file, props.patient);
  if (ok) showCameraModal.value = false;
};

// ── Phone search wiring ────────────────────────────────────────
const phoneSearchState = computed(() => ({
  searching: phoneContactSearching.value,
  patients: phonePatientResults.value,
  contacts: phoneContactResults.value,
  dropdownVisible: phoneContactDropdown.value,
}));

const onPhoneInput = masked => {
  searchPhone(masked.replace(/\D/g, ''));
};

const onPhoneFocus = () => {
  phoneContactDropdown.value =
    phoneContactResults.value.length > 0 ||
    phonePatientResults.value.length > 0;
};

const onPhoneBlur = () => {
  setTimeout(() => {
    phoneContactDropdown.value = false;
  }, 200);
};

const onSelectPhoneContact = contact => {
  skipNextPhoneSearch();
  props.patient.contact_id = contact.id;
  let digits = String(contact.phone_number || '').replace(/\D/g, '');
  if (digits.startsWith('55')) digits = digits.slice(2);
  props.patient.phone = formatPhoneDisplay(digits) || maskPhone(digits);
  if (contact.email && !props.patient.email) {
    props.patient.email = contact.email;
  }
  resetPhoneSearch();
};

const onSelectPhonePatient = existingPatient => {
  resetPhoneSearch();
  router.push({
    name: 'patients_dashboard_record',
    params: {
      accountId: route.params.accountId,
      patientId: existingPatient.id,
    },
  });
};

// ── CEP autosearch (precisa do address ref) ─────────────────────
watch(
  () => props.patient?.address?.zip_code,
  newVal => {
    if (!newVal) return;
    let value = String(newVal).replace(/\D/g, '');
    if (value.length > 8) value = value.slice(0, 8);

    let formatted = value;
    if (value.length > 5) {
      formatted = value.replace(/(\d{5})(\d{1,3})/, '$1-$2');
    }
    if (newVal !== formatted) {
      if (!props.patient.address) props.patient.address = {};
      props.patient.address.zip_code = formatted;
      return; // re-trigger watcher
    }
    if (value.length === 8 && cepUserDirty.value) {
      searchCep(props.patient.address, false);
    }
  }
);

// ── Save (combina first/last antes de chamar) ──────────────────
const handleSave = () => {
  props.patient.name = `${editFirstName.value} ${editLastName.value}`.trim();
  saveRegistration(props.patient);
};

onMounted(() => {
  initEditNameFromPatient();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <RegistrationHeader
      :updated-at="patient.updated_at"
      :is-loading="isLoading"
      @save="handleSave"
    />

    <div class="reg-form-grid">
      <RegistrationPersonalSection
        :patient="patient"
        :first-name="editFirstName"
        :last-name="editLastName"
        :expanded="regSections.personal"
        @update:expanded="regSections.personal = $event"
        @update:first-name="editFirstName = $event"
        @update:last-name="editLastName = $event"
        @avatar-file="handleAvatarFile"
        @open-camera="showCameraModal = true"
      />

      <RegistrationContactSection
        :patient="patient"
        :expanded="regSections.contact"
        :phone-search-state="phoneSearchState"
        @update:expanded="regSections.contact = $event"
        @phone-input="onPhoneInput"
        @phone-focus="onPhoneFocus"
        @phone-blur="onPhoneBlur"
        @select-patient="onSelectPhonePatient"
        @select-contact="onSelectPhoneContact"
      />

      <RegistrationAddressSection
        :patient="patient"
        :expanded="regSections.address"
        @update:expanded="regSections.address = $event"
        @mark-cep-dirty="markCepDirty"
        @search-cep="searchCep(patient.address, true)"
      />

      <RegistrationAdminSection
        :patient="patient"
        :expanded="regSections.admin"
        @update:expanded="regSections.admin = $event"
      />
    </div>
  </div>

  <CameraCaptureModal
    :open="showCameraModal"
    @close="showCameraModal = false"
    @use-photo="handleCameraPhoto"
  />
</template>
