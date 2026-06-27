<script setup>
import { useI18n } from 'vue-i18n';
import {
  maskPhone,
  formatPhoneDisplay,
} from '@plugins/patients/frontend/features/patient-record/utils/registrationMasks';
import PhoneContactDropdown from './PhoneContactDropdown.vue';

const props = defineProps({
  patient: { type: Object, required: true },
  expanded: { type: Boolean, default: true },
  phoneSearchState: {
    type: Object,
    default: () => ({
      searching: false,
      patients: [],
      contacts: [],
      dropdownVisible: false,
    }),
  },
});

const emit = defineEmits([
  'update:expanded',
  'phone-input',
  'phone-focus',
  'phone-blur',
  'select-patient',
  'select-contact',
]);

const { t } = useI18n();

const handlePhoneInput = event => {
  const masked = maskPhone(event.target.value);
  props.patient.phone = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
  emit('phone-input', masked);
};

const handleAlternativePhoneInput = event => {
  const masked = maskPhone(event.target.value);
  if (!props.patient.emergency_contact) props.patient.emergency_contact = {};
  props.patient.emergency_contact.phone = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
};

const toggleWhatsappOptIn = () => {
  if (!props.patient.communication_opt_ins) {
    props.patient.communication_opt_ins = {};
  }
  props.patient.communication_opt_ins.whatsapp =
    !props.patient.communication_opt_ins.whatsapp;
};

const toggleEmailOptIn = () => {
  if (!props.patient.communication_opt_ins) {
    props.patient.communication_opt_ins = {};
  }
  props.patient.communication_opt_ins.email =
    !props.patient.communication_opt_ins.email;
};
</script>

<template>
  <div class="reg-section">
    <button
      class="reg-section-toggle"
      @click="emit('update:expanded', !expanded)"
    >
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-green">
          <i class="i-lucide-phone w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_REGISTRATION.SECTIONS.CONTACT.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_REGISTRATION.SECTIONS.CONTACT.SUBTITLE') }}
          </span>
        </div>
      </div>
      <i
        class="i-lucide-chevron-down w-4 h-4 reg-chevron"
        :class="{ 'reg-chevron-open': expanded }"
      />
    </button>

    <div v-if="expanded" class="reg-section-body">
      <div class="reg-field-grid-2">
        <div class="form-group reg-field-relative">
          <label>
            {{ t('PATIENT_REGISTRATION.CONTACT.PHONE_LABEL') }}
            <span class="reg-badge-wpp">
              <i class="i-ri-whatsapp-fill w-3 h-3" />
              {{ t('PATIENT_REGISTRATION.CONTACT.WHATSAPP_BADGE') }}
            </span>
            <span class="reg-required">*</span>
          </label>
          <input
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.CONTACT.PHONE_PLACEHOLDER')"
            :value="formatPhoneDisplay(patient.phone)"
            autocomplete="off"
            @focus="emit('phone-focus')"
            @blur="emit('phone-blur')"
            @input="handlePhoneInput"
          />
          <PhoneContactDropdown
            :visible="phoneSearchState.dropdownVisible"
            :searching="phoneSearchState.searching"
            :patients="phoneSearchState.patients"
            :contacts="phoneSearchState.contacts"
            @select-patient="$event => emit('select-patient', $event)"
            @select-contact="$event => emit('select-contact', $event)"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.CONTACT.ALT_PHONE') }}</label>
          <input
            :value="formatPhoneDisplay(patient.emergency_contact?.phone)"
            type="text"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.CONTACT.ALT_PHONE_PLACEHOLDER')"
            @input="handleAlternativePhoneInput"
          />
        </div>
      </div>

      <div class="form-group">
        <label>{{ t('PATIENT_REGISTRATION.CONTACT.EMAIL') }}</label>
        <input
          v-model="patient.email"
          type="email"
          class="form-input"
          :placeholder="t('PATIENT_REGISTRATION.CONTACT.EMAIL_PLACEHOLDER')"
        />
      </div>

      <div class="reg-divider" />

      <p class="reg-subsection-label">
        {{ t('PATIENT_REGISTRATION.CONTACT.PREFERENCES_TITLE') }}
      </p>
      <div class="reg-opt-in-grid">
        <label class="reg-opt-in-card">
          <div class="reg-opt-in-info">
            <i class="i-lucide-message-circle w-4 h-4 text-green-400" />
            <div>
              <p class="text-sm font-medium text-slate-200">
                {{ t('PATIENT_REGISTRATION.CONTACT.WHATSAPP_TITLE') }}
              </p>
              <p class="text-xs text-slate-500">
                {{ t('PATIENT_REGISTRATION.CONTACT.WHATSAPP_HINT') }}
              </p>
            </div>
          </div>
          <div
            class="reg-toggle"
            :class="{
              'reg-toggle-on': patient.communication_opt_ins?.whatsapp,
            }"
            @click="toggleWhatsappOptIn"
          >
            <div class="reg-toggle-thumb" />
          </div>
        </label>
        <label class="reg-opt-in-card">
          <div class="reg-opt-in-info">
            <i class="i-lucide-mail w-4 h-4 text-blue-400" />
            <div>
              <p class="text-sm font-medium text-slate-200">
                {{ t('PATIENT_REGISTRATION.CONTACT.EMAIL_TITLE') }}
              </p>
              <p class="text-xs text-slate-500">
                {{ t('PATIENT_REGISTRATION.CONTACT.EMAIL_HINT') }}
              </p>
            </div>
          </div>
          <div
            class="reg-toggle"
            :class="{ 'reg-toggle-on': patient.communication_opt_ins?.email }"
            @click="toggleEmailOptIn"
          >
            <div class="reg-toggle-thumb" />
          </div>
        </label>
      </div>
    </div>
  </div>
</template>
