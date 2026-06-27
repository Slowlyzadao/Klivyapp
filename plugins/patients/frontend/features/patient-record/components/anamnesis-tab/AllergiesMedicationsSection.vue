<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  anamnesis: { type: Object, required: true },
  allergyInput: { type: String, default: '' },
  medicationInput: { type: String, default: '' },
});

const emit = defineEmits([
  'update:allergyInput',
  'update:medicationInput',
  'flush-allergy',
  'flush-medication',
  'remove-allergy',
  'remove-medication',
]);

const { t } = useI18n();

const isFinalized = computed(() => props.anamnesis.status === 'finalized');
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-red">
          <i class="i-lucide-pill w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.SUBTITLE') }}
          </span>
        </div>
      </div>
    </div>
    <div class="reg-section-body">
      <div class="reg-field-grid-2">
        <div class="form-group">
          <label class="form-label anm-label-danger">
            <i class="i-lucide-triangle-alert w-3.5 h-3.5" />
            {{ t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.ALLERGIES_LABEL') }}
            <span class="reg-required">*</span>
          </label>
          <input
            :value="allergyInput"
            type="text"
            class="form-input anm-input-danger"
            :placeholder="
              t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.ALLERGIES_PLACEHOLDER')
            "
            :disabled="isFinalized"
            @input="emit('update:allergyInput', $event.target.value)"
            @blur="emit('flush-allergy')"
          />
          <div v-if="anamnesis.allergies?.length" class="anm-tags-row">
            <span
              v-for="(alg, idx) in anamnesis.allergies"
              :key="idx"
              class="anm-tag anm-tag--red"
            >
              {{ alg.name }}
              <button
                v-if="!isFinalized"
                type="button"
                class="anm-tag-remove"
                :aria-label="
                  t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.REMOVE_ARIA', {
                    name: alg.name,
                  })
                "
                @click="emit('remove-allergy', idx)"
              >
                <i class="i-lucide-x w-3 h-3" />
              </button>
            </span>
          </div>
        </div>
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.MEDICATIONS_LABEL') }}
          </label>
          <input
            :value="medicationInput"
            type="text"
            class="form-input"
            :placeholder="
              t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.MEDICATIONS_PLACEHOLDER')
            "
            :disabled="isFinalized"
            @input="emit('update:medicationInput', $event.target.value)"
            @blur="emit('flush-medication')"
          />
          <div v-if="anamnesis.current_medications?.length" class="anm-tags-row">
            <span
              v-for="(med, idx) in anamnesis.current_medications"
              :key="idx"
              class="anm-tag anm-tag--blue"
            >
              {{ med.name }}
              <button
                v-if="!isFinalized"
                type="button"
                class="anm-tag-remove"
                :aria-label="
                  t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.REMOVE_ARIA', {
                    name: med.name,
                  })
                "
                @click="emit('remove-medication', idx)"
              >
                <i class="i-lucide-x w-3 h-3" />
              </button>
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
