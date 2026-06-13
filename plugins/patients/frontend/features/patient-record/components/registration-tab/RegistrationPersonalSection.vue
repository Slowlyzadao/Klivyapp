<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  formatDateBR,
  brToIsoDate,
  maskDateBR,
} from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import {
  maskCpf,
  maskPhone,
  formatCpfDisplay,
} from '@plugins/patients/frontend/features/patient-record/utils/registrationMasks';
import {
  SEX_OPTIONS,
  MARITAL_STATUS_OPTIONS,
  GUARDIAN_RELATIONSHIP_OPTIONS,
} from '@plugins/patients/frontend/constants/registration';
import AvatarUploadCard from './AvatarUploadCard.vue';

const props = defineProps({
  patient: { type: Object, required: true },
  expanded: { type: Boolean, default: true },
  firstName: { type: String, default: '' },
  lastName: { type: String, default: '' },
});

const emit = defineEmits([
  'update:expanded',
  'update:firstName',
  'update:lastName',
  'avatar-file',
  'open-camera',
]);

const { t } = useI18n();

const birthdateDisplay = ref('');

watch(
  () => props.patient?.birthdate,
  iso => {
    birthdateDisplay.value = iso ? formatDateBR(iso) : '';
  },
  { immediate: true }
);

const handleBirthdateInput = event => {
  const masked = maskDateBR(event.target.value);
  birthdateDisplay.value = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
  if (masked.length === 10) {
    const iso = brToIsoDate(masked);
    if (iso) props.patient.birthdate = iso;
  } else if (masked.length === 0) {
    props.patient.birthdate = '';
  }
};

const handleBirthdateBlur = () => {
  birthdateDisplay.value = props.patient?.birthdate
    ? formatDateBR(props.patient.birthdate)
    : '';
};

const handleCpfInput = event => {
  const masked = maskCpf(event.target.value);
  props.patient.cpf = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
};

const handleGuardianCpfInput = event => {
  const masked = maskCpf(event.target.value);
  if (!props.patient.guardian) props.patient.guardian = {};
  props.patient.guardian.cpf = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
};

const handleGuardianPhoneInput = event => {
  const masked = maskPhone(event.target.value);
  if (!props.patient.guardian) props.patient.guardian = {};
  props.patient.guardian.phone = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
};

watch(
  () => props.patient?.has_guardian,
  (newVal, oldVal) => {
    if (oldVal === true && newVal === false) {
      props.patient.guardian = {
        name: '',
        cpf: '',
        phone: '',
        relationship: '',
      };
    }
  }
);

const toggleGuardian = () => {
  props.patient.has_guardian = !props.patient.has_guardian;
};
</script>

<template>
  <div class="reg-section">
    <button
      class="reg-section-toggle"
      @click="emit('update:expanded', !expanded)"
    >
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-blue">
          <i class="i-lucide-user w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_REGISTRATION.SECTIONS.PERSONAL.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_REGISTRATION.SECTIONS.PERSONAL.SUBTITLE') }}
          </span>
        </div>
      </div>
      <i
        class="i-lucide-chevron-down w-4 h-4 reg-chevron"
        :class="{ 'reg-chevron-open': expanded }"
      />
    </button>

    <div v-if="expanded" class="reg-section-body">
      <AvatarUploadCard
        :avatar-url="patient.avatar_url"
        :patient-name="patient.name"
        @file-selected="file => emit('avatar-file', file)"
        @open-camera="emit('open-camera')"
      />

      <div class="reg-divider" />

      <div class="reg-field-grid-3">
        <div class="form-group">
          <label>
            {{ t('PATIENT_REGISTRATION.PERSONAL.FIRST_NAME') }}
            <span class="reg-required">*</span>
          </label>
          <input
            :value="firstName"
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.FIRST_NAME_PLACEHOLDER')"
            @input="emit('update:firstName', $event.target.value)"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.PERSONAL.LAST_NAME') }}</label>
          <input
            :value="lastName"
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.LAST_NAME_PLACEHOLDER')"
            @input="emit('update:lastName', $event.target.value)"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.PERSONAL.SOCIAL_NAME') }}</label>
          <input
            v-model="patient.social_name"
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.SOCIAL_NAME_PLACEHOLDER')"
          />
        </div>
      </div>

      <div class="reg-field-grid-3">
        <div class="form-group">
          <label>
            {{ t('PATIENT_REGISTRATION.PERSONAL.BIRTHDATE') }}
            <span class="reg-required">*</span>
          </label>
          <input
            :value="birthdateDisplay"
            type="text"
            inputmode="numeric"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.BIRTHDATE_PLACEHOLDER')"
            maxlength="10"
            autocomplete="bday"
            @input="handleBirthdateInput"
            @blur="handleBirthdateBlur"
          />
        </div>
        <div class="form-group">
          <label>
            {{ t('PATIENT_REGISTRATION.PERSONAL.SEX') }}
            <span class="reg-required">*</span>
          </label>
          <FormSelect
            v-model="patient.sex"
            :options="SEX_OPTIONS"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.SELECT_PLACEHOLDER')"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.PERSONAL.MARITAL') }}</label>
          <FormSelect
            v-model="patient.marital_status"
            :options="MARITAL_STATUS_OPTIONS"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.SELECT_PLACEHOLDER')"
            clearable
          />
        </div>
      </div>

      <div class="reg-field-grid-2">
        <div class="form-group">
          <label>
            {{ t('PATIENT_REGISTRATION.PERSONAL.CPF') }}
            <span class="reg-required">*</span>
          </label>
          <input
            :value="formatCpfDisplay(patient.cpf)"
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.CPF_PLACEHOLDER')"
            @input="handleCpfInput"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.PERSONAL.RG') }}</label>
          <input
            v-model="patient.rg"
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.PERSONAL.RG_PLACEHOLDER')"
            maxlength="20"
          />
        </div>
      </div>

      <div class="form-group">
        <label>{{ t('PATIENT_REGISTRATION.PERSONAL.NOTES') }}</label>
        <textarea
          v-model="patient.notes"
          class="form-input reg-textarea"
          rows="3"
          :placeholder="t('PATIENT_REGISTRATION.PERSONAL.NOTES_PLACEHOLDER')"
          maxlength="2000"
        />
      </div>

      <div class="reg-divider" />

      <!-- Toggle responsável -->
      <div
        class="reg-toggle-row"
        role="switch"
        tabindex="0"
        :aria-checked="Boolean(patient.has_guardian)"
        @click="toggleGuardian"
        @keydown.space.prevent="toggleGuardian"
        @keydown.enter.prevent="toggleGuardian"
      >
        <div class="reg-toggle-row-text">
          <p class="reg-toggle-row-title">
            {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_TOGGLE_TITLE') }}
          </p>
          <p class="reg-toggle-row-hint">
            {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_TOGGLE_HINT') }}
          </p>
        </div>
        <div class="reg-toggle" :class="{ 'reg-toggle-on': patient.has_guardian }">
          <div class="reg-toggle-thumb" />
        </div>
      </div>

      <transition name="reg-collapse">
        <div v-if="patient.has_guardian" class="reg-guardian-block">
          <p class="reg-subsection-label">
            {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_BLOCK_TITLE') }}
          </p>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label>
                {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_NAME') }}
                <span class="reg-required">*</span>
              </label>
              <input
                v-model="patient.guardian.name"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_NAME_PLACEHOLDER')"
              />
            </div>
            <div class="form-group">
              <label>
                {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_RELATIONSHIP') }}
                <span class="reg-required">*</span>
              </label>
              <FormSelect
                v-model="patient.guardian.relationship"
                :options="GUARDIAN_RELATIONSHIP_OPTIONS"
                :placeholder="
                  t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_RELATIONSHIP_PLACEHOLDER')
                "
                clearable
              />
            </div>
          </div>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label>
                {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_CPF') }}
                <span class="reg-required">*</span>
              </label>
              <input
                :value="formatCpfDisplay(patient.guardian?.cpf)"
                type="text"
                class="form-input"
                :placeholder="t('PATIENT_REGISTRATION.PERSONAL.CPF_PLACEHOLDER')"
                @input="handleGuardianCpfInput"
              />
            </div>
            <div class="form-group">
              <label>
                {{ t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_PHONE') }}
                <span class="reg-required">*</span>
              </label>
              <input
                :value="patient.guardian?.phone"
                type="text"
                inputmode="numeric"
                class="form-input"
                :placeholder="t('PATIENT_REGISTRATION.PERSONAL.GUARDIAN_PHONE_PLACEHOLDER')"
                @input="handleGuardianPhoneInput"
              />
            </div>
          </div>
        </div>
      </transition>
    </div>
  </div>
</template>
