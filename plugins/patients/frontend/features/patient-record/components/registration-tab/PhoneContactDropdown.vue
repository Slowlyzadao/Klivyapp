<script setup>
import { useI18n } from 'vue-i18n';
import {
  formatPhoneDisplay,
  phoneContactColor,
} from '@plugins/patients/frontend/features/patient-record/utils/registrationMasks';

defineProps({
  visible: { type: Boolean, default: false },
  searching: { type: Boolean, default: false },
  patients: { type: Array, default: () => [] },
  contacts: { type: Array, default: () => [] },
});

const emit = defineEmits(['select-patient', 'select-contact']);

const { t } = useI18n();

const firstChar = name => (name || '?')[0].toUpperCase();
</script>

<template>
  <div
    v-if="visible && (searching || patients.length > 0 || contacts.length > 0)"
    class="reg-contact-dropdown"
  >
    <div v-if="searching" class="reg-dropdown-loading">
      {{ t('PATIENT_REGISTRATION.CONTACT.DROPDOWN.SEARCHING') }}
    </div>
    <template v-else>
      <!-- Pacientes existentes (priority) -->
      <div v-if="patients.length > 0" class="reg-dropdown-section">
        <div class="reg-dropdown-section-header">
          <i
            class="i-lucide-user-check w-3 h-3 reg-dropdown-section-icon reg-dropdown-section-icon--patient"
          />
          {{ t('PATIENT_REGISTRATION.CONTACT.DROPDOWN.PATIENTS_HEADER') }}
          <span class="reg-dropdown-section-count">{{ patients.length }}</span>
        </div>
        <ul class="reg-dropdown-list">
          <li
            v-for="p in patients"
            :key="`pat-${p.id}`"
            class="reg-dropdown-item reg-dropdown-item--patient"
            @mousedown.prevent="emit('select-patient', p)"
          >
            <span
              v-if="p.avatar_url"
              class="reg-item-avatar reg-item-avatar--img"
            >
              <img :src="p.avatar_url" :alt="p.name" />
            </span>
            <span
              v-else
              class="reg-item-avatar"
              :style="{ background: phoneContactColor(p.name) }"
            >
              {{ firstChar(p.name) }}
            </span>
            <div class="reg-item-info">
              <span class="reg-item-name">
                {{
                  p.name || t('PATIENT_REGISTRATION.CONTACT.DROPDOWN.NO_NAME')
                }}
              </span>
              <span class="reg-item-phone">
                {{
                  formatPhoneDisplay(p.phone) ||
                  p.phone ||
                  t('PATIENT_REGISTRATION.CONTACT.DROPDOWN.NO_PHONE')
                }}
              </span>
            </div>
            <i class="i-lucide-arrow-right w-4 h-4 reg-dropdown-arrow" />
          </li>
        </ul>
      </div>

      <div
        v-if="patients.length > 0 && contacts.length > 0"
        class="reg-dropdown-divider"
      />

      <!-- Contatos do chat -->
      <div v-if="contacts.length > 0" class="reg-dropdown-section">
        <div class="reg-dropdown-section-header">
          <i
            class="i-lucide-message-circle w-3 h-3 reg-dropdown-section-icon reg-dropdown-section-icon--contact"
          />
          {{ t('PATIENT_REGISTRATION.CONTACT.DROPDOWN.CHAT_CONTACTS_HEADER') }}
          <span class="reg-dropdown-section-count">{{ contacts.length }}</span>
        </div>
        <ul class="reg-dropdown-list">
          <li
            v-for="contact in contacts"
            :key="`ct-${contact.id}`"
            class="reg-dropdown-item"
            @mousedown.prevent="emit('select-contact', contact)"
          >
            <span
              v-if="contact.avatar_url"
              class="reg-item-avatar reg-item-avatar--img"
            >
              <img :src="contact.avatar_url" :alt="contact.name" />
            </span>
            <span
              v-else
              class="reg-item-avatar"
              :style="{ background: phoneContactColor(contact.name) }"
            >
              {{ firstChar(contact.name) }}
            </span>
            <div class="reg-item-info">
              <span class="reg-item-name">
                {{
                  contact.name ||
                  t('PATIENT_REGISTRATION.CONTACT.DROPDOWN.NO_NAME')
                }}
              </span>
              <span class="reg-item-phone">{{ contact.phone_number }}</span>
            </div>
          </li>
        </ul>
      </div>
    </template>
  </div>
</template>
