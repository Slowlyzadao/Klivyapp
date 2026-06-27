<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import {
  formatDateBR,
  brToIsoDate,
  maskDateBR,
} from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import {
  maskPhone,
  formatPhoneDisplay,
} from '@plugins/patients/frontend/features/patient-record/utils/registrationMasks';
import { INSURANCE_OPTIONS } from '@plugins/patients/frontend/constants/registration';

const props = defineProps({
  patient: { type: Object, required: true },
  expanded: { type: Boolean, default: false },
});

const emit = defineEmits(['update:expanded']);

const { t } = useI18n();
const store = useStore();

// Lista de agents da conta pra popular o dropdown "Profissional Responsável".
// Inclui opção "Sem profissional atribuído" (null) pra permitir desatribuir.
// NÃO filtra por `confirmed`: agents pendentes de verificação por email ainda
// existem na conta e podem ser atribuídos como responsáveis. O filtro só
// significava "ainda não aceitaram o convite", não "inativos".
const agentOptions = computed(() => {
  const agents = store.getters['agents/getAgents'] || [];
  return [
    { value: null, label: 'Sem profissional atribuído' },
    ...agents.map(a => ({
      value: a.id,
      label: a.role ? `${a.name} · ${a.role}` : a.name,
    })),
  ];
});

// Garante objetos aninhados para v-model.
const ensureShape = () => {
  if (!props.patient.insurance) props.patient.insurance = {};
  if (!props.patient.emergency_contact) props.patient.emergency_contact = {};
  if (!props.patient.lgpd_consent) props.patient.lgpd_consent = {};
};
ensureShape();

// ── Validade carteirinha (mesma máscara da data de nascimento) ──
const validityDisplay = ref('');

watch(
  () => props.patient?.insurance?.validity,
  iso => {
    validityDisplay.value = iso ? formatDateBR(iso) : '';
  },
  { immediate: true }
);

const handleValidityInput = event => {
  const masked = maskDateBR(event.target.value);
  validityDisplay.value = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
  if (!props.patient.insurance) props.patient.insurance = {};
  if (masked.length === 10) {
    const iso = brToIsoDate(masked);
    if (iso) props.patient.insurance.validity = iso;
  } else if (masked.length === 0) {
    props.patient.insurance.validity = '';
  }
};

const handleValidityBlur = () => {
  validityDisplay.value = props.patient?.insurance?.validity
    ? formatDateBR(props.patient.insurance.validity)
    : '';
};

const handleEmergencyPhoneInput = event => {
  const masked = maskPhone(event.target.value);
  if (!props.patient.emergency_contact) props.patient.emergency_contact = {};
  props.patient.emergency_contact.phone = masked;
  // eslint-disable-next-line no-param-reassign
  event.target.value = masked;
};

const toggleLgpdConsent = key => {
  if (!props.patient.lgpd_consent) props.patient.lgpd_consent = {};
  props.patient.lgpd_consent[key] = !props.patient.lgpd_consent[key];
};
</script>

<template>
  <div class="reg-section">
    <button
      class="reg-section-toggle"
      @click="emit('update:expanded', !expanded)"
    >
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-purple">
          <i class="i-lucide-briefcase w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_REGISTRATION.SECTIONS.ADMIN.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_REGISTRATION.SECTIONS.ADMIN.SUBTITLE') }}
          </span>
        </div>
      </div>
      <i
        class="i-lucide-chevron-down w-4 h-4 reg-chevron"
        :class="{ 'reg-chevron-open': expanded }"
      />
    </button>

    <div v-if="expanded" class="reg-section-body">
      <!-- Profissional Responsável (F-13 melhoria UX, 2026-05-11):
           campo opcional pra recepção atribuir já no cadastro, antes do
           callback automático na 1ª ação (agendar/atender/cobrar). Vazio
           = "Sem profissional atribuído" (UI mostra empty state honesto). -->
      <p class="reg-subsection-label">Profissional Responsável</p>
      <div class="reg-field-grid-2">
        <div class="form-group" style="grid-column: 1 / -1">
          <label>Atribuir profissional responsável</label>
          <FormSelect
            v-model="patient.responsible_professional_id"
            :options="agentOptions"
            placeholder="Selecione um profissional..."
          />
          <small class="reg-field-hint">
            Quem cuida regularmente do paciente. Se deixar vazio, será
            preenchido automaticamente quando alguém agendar, criar plano,
            atender ou cobrar pela primeira vez.
          </small>
        </div>
      </div>

      <p class="reg-subsection-label">
        {{ t('PATIENT_REGISTRATION.ADMIN.INSURANCE_TITLE') }}
      </p>
      <div class="reg-field-grid-2">
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADMIN.INSURANCE_NAME') }}</label>
          <FormSelect
            v-model="patient.insurance.name"
            :options="INSURANCE_OPTIONS"
            :placeholder="
              t('PATIENT_REGISTRATION.ADMIN.INSURANCE_NAME_PLACEHOLDER')
            "
            clearable
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADMIN.INSURANCE_NUMBER') }}</label>
          <input
            v-model="patient.insurance.number"
            type="text"
            class="form-input"
            :placeholder="
              t('PATIENT_REGISTRATION.ADMIN.INSURANCE_NUMBER_PLACEHOLDER')
            "
          />
        </div>
      </div>
      <div class="reg-field-grid-2">
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADMIN.INSURANCE_PLAN') }}</label>
          <input
            v-model="patient.insurance.plan"
            type="text"
            class="form-input"
            :placeholder="
              t('PATIENT_REGISTRATION.ADMIN.INSURANCE_PLAN_PLACEHOLDER')
            "
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADMIN.INSURANCE_VALIDITY') }}</label>
          <input
            :value="validityDisplay"
            type="text"
            inputmode="numeric"
            class="form-input"
            :placeholder="
              t('PATIENT_REGISTRATION.ADMIN.INSURANCE_VALIDITY_PLACEHOLDER')
            "
            maxlength="10"
            @input="handleValidityInput"
            @blur="handleValidityBlur"
          />
        </div>
      </div>

      <div class="reg-divider" />

      <p class="reg-subsection-label">
        {{ t('PATIENT_REGISTRATION.ADMIN.EMERGENCY_TITLE') }}
      </p>
      <div class="reg-field-grid-3">
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADMIN.EMERGENCY_NAME') }}</label>
          <input
            v-model="patient.emergency_contact.name"
            type="text"
            class="form-input"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADMIN.EMERGENCY_PHONE') }}</label>
          <input
            :value="formatPhoneDisplay(patient.emergency_contact.phone)"
            type="text"
            inputmode="tel"
            class="form-input"
            :placeholder="t('PATIENT_REGISTRATION.CONTACT.ALT_PHONE_PLACEHOLDER')"
            @input="handleEmergencyPhoneInput"
          />
        </div>
        <div class="form-group">
          <label>
            {{ t('PATIENT_REGISTRATION.ADMIN.EMERGENCY_RELATIONSHIP') }}
          </label>
          <input
            v-model="patient.emergency_contact.relationship"
            type="text"
            class="form-input"
            :placeholder="
              t('PATIENT_REGISTRATION.ADMIN.EMERGENCY_RELATIONSHIP_PLACEHOLDER')
            "
          />
        </div>
      </div>

      <div class="reg-divider" />

      <p class="reg-subsection-label">
        {{ t('PATIENT_REGISTRATION.ADMIN.LGPD_TITLE') }}
      </p>
      <div class="reg-opt-in-grid">
        <label class="reg-opt-in-card">
          <div class="reg-opt-in-info">
            <i class="i-lucide-shield-check w-4 h-4 text-blue-400" />
            <div>
              <p class="text-sm font-medium text-slate-200">
                {{ t('PATIENT_REGISTRATION.ADMIN.LGPD_TERM') }}
              </p>
              <p class="text-xs text-slate-500">
                {{ t('PATIENT_REGISTRATION.ADMIN.LGPD_TERM_HINT') }}
              </p>
            </div>
          </div>
          <div
            class="reg-toggle"
            :class="{ 'reg-toggle-on': patient.lgpd_consent.accepted }"
            @click="toggleLgpdConsent('accepted')"
          >
            <div class="reg-toggle-thumb" />
          </div>
        </label>
        <label class="reg-opt-in-card">
          <div class="reg-opt-in-info">
            <i class="i-lucide-image w-4 h-4 text-purple-400" />
            <div>
              <p class="text-sm font-medium text-slate-200">
                {{ t('PATIENT_REGISTRATION.ADMIN.LGPD_IMAGE') }}
              </p>
              <p class="text-xs text-slate-500">
                {{ t('PATIENT_REGISTRATION.ADMIN.LGPD_IMAGE_HINT') }}
              </p>
            </div>
          </div>
          <div
            class="reg-toggle"
            :class="{
              'reg-toggle-on': patient.lgpd_consent.image_use_accepted,
            }"
            @click="toggleLgpdConsent('image_use_accepted')"
          >
            <div class="reg-toggle-thumb" />
          </div>
        </label>
      </div>
    </div>
  </div>
</template>
