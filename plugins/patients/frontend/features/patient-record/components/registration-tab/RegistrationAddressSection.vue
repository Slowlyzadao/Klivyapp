<script setup>
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import { UF_OPTIONS } from '@plugins/patients/frontend/constants/registration';

const props = defineProps({
  patient: { type: Object, required: true },
  expanded: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:expanded',
  'mark-cep-dirty',
  'search-cep',
]);

const { t } = useI18n();

// Garante que patient.address exista para evitar v-model em undefined.
const ensureAddress = () => {
  if (!props.patient.address) props.patient.address = {};
};
ensureAddress();
</script>

<template>
  <div class="reg-section">
    <button
      class="reg-section-toggle"
      @click="emit('update:expanded', !expanded)"
    >
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-amber">
          <i class="i-lucide-map-pin w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_REGISTRATION.SECTIONS.ADDRESS.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_REGISTRATION.SECTIONS.ADDRESS.SUBTITLE') }}
          </span>
        </div>
      </div>
      <i
        class="i-lucide-chevron-down w-4 h-4 reg-chevron"
        :class="{ 'reg-chevron-open': expanded }"
      />
    </button>

    <div v-if="expanded" class="reg-section-body">
      <div class="reg-field-grid-cep">
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.ZIP') }}</label>
          <div class="input-with-action">
            <input
              v-model="patient.address.zip_code"
              type="text"
              class="form-input"
              :placeholder="t('PATIENT_REGISTRATION.ADDRESS.ZIP_PLACEHOLDER')"
              @input="emit('mark-cep-dirty')"
            />
            <button class="btn-icon-inside" @click.prevent="emit('search-cep')">
              <i class="i-lucide-search w-4 h-4" />
            </button>
          </div>
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.STREET') }}</label>
          <input
            v-model="patient.address.street"
            type="text"
            class="form-input"
          />
        </div>
      </div>

      <div class="reg-field-grid-3">
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.NUMBER') }}</label>
          <input
            v-model="patient.address.number"
            type="text"
            class="form-input"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.COMPLEMENT') }}</label>
          <input
            v-model="patient.address.complement"
            type="text"
            class="form-input"
            :placeholder="
              t('PATIENT_REGISTRATION.ADDRESS.COMPLEMENT_PLACEHOLDER')
            "
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.NEIGHBORHOOD') }}</label>
          <input
            v-model="patient.address.neighborhood"
            type="text"
            class="form-input"
          />
        </div>
      </div>

      <div class="reg-field-grid-2">
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.CITY') }}</label>
          <input
            v-model="patient.address.city"
            type="text"
            class="form-input"
          />
        </div>
        <div class="form-group">
          <label>{{ t('PATIENT_REGISTRATION.ADDRESS.STATE') }}</label>
          <FormSelect
            v-model="patient.address.state"
            :options="UF_OPTIONS"
            :placeholder="t('PATIENT_REGISTRATION.ADDRESS.STATE_PLACEHOLDER')"
            searchable
            clearable
          />
        </div>
      </div>
    </div>
  </div>
</template>
