<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  CONSENT_TYPES,
  EXPIRY_OPTIONS,
} from '@plugins/patients/frontend/constants/consents';
import { fillConsentTemplate } from '@plugins/patients/frontend/features/patient-record/utils/consentTemplates';

const props = defineProps({
  patient: { type: Object, required: true },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'create']);

const { t } = useI18n();

const blankForm = () => ({
  consent_type: '',
  title: '',
  body: '',
  expires_in_months: 12,
  observations: '',
});

const form = ref(blankForm());

// Reset on parent re-mount.
watch(
  () => props.patient?.id,
  () => {
    form.value = blankForm();
  }
);

const consentTypeOptions = CONSENT_TYPES.map(c => ({
  value: c.value,
  label: c.label,
}));

const consentTypeDetail = computed(() =>
  CONSENT_TYPES.find(c => c.value === form.value.consent_type)
);

const onTypeChange = () => {
  const detail = consentTypeDetail.value;
  if (!detail) return;
  form.value.title = detail.label;
  form.value.body = fillConsentTemplate(detail.template, props.patient);
};

const handleCreate = () => {
  if (!form.value.consent_type || !form.value.title) return;
  emit('create', {
    title: form.value.title,
    document_type: form.value.consent_type,
    body: form.value.body,
    expires_after_days: form.value.expires_in_months * 30,
    observations: form.value.observations,
  });
};

defineExpose({
  reset: () => {
    form.value = blankForm();
  },
});
</script>

<template>
  <div class="reg-section mb-5">
    <div class="reg-section-toggle consent-form-header">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-green">
          <i class="i-lucide-plus-circle w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_CONSENTS.FORM.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_CONSENTS.FORM.SUBTITLE') }}
          </span>
        </div>
      </div>
      <BeclinicButton
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-x"
        :title="t('PATIENT_CONSENTS.FORM.CLOSE')"
        @click="emit('close')"
      />
    </div>

    <div class="reg-section-body">
      <div class="grid grid-cols-12 gap-4">
        <div class="col-span-4 form-group">
          <label class="form-label">
            {{ t('PATIENT_CONSENTS.FORM.TYPE_LABEL') }}
            <span class="reg-required">*</span>
          </label>
          <FormSelect
            v-model="form.consent_type"
            :options="consentTypeOptions"
            :placeholder="t('PATIENT_CONSENTS.FORM.TYPE_PLACEHOLDER')"
            auto-searchable
            @update:model-value="onTypeChange"
          />
          <p
            v-if="consentTypeDetail"
            class="text-xs text-slate-500 mt-1.5 leading-snug"
          >
            {{ consentTypeDetail.description }}
          </p>
        </div>
        <div class="col-span-5 form-group">
          <label class="form-label">
            {{ t('PATIENT_CONSENTS.FORM.DOCUMENT_TITLE_LABEL') }}
          </label>
          <input
            v-model="form.title"
            type="text"
            :placeholder="t('PATIENT_CONSENTS.FORM.DOCUMENT_TITLE_PLACEHOLDER')"
            class="form-input"
          />
        </div>
        <div class="col-span-3 form-group">
          <label class="form-label">
            {{ t('PATIENT_CONSENTS.FORM.VALIDITY_LABEL') }}
          </label>
          <FormSelect
            v-model="form.expires_in_months"
            :options="EXPIRY_OPTIONS"
            :placeholder="t('PATIENT_CONSENTS.FORM.VALIDITY_PLACEHOLDER')"
          />
        </div>
      </div>

      <div class="form-group">
        <label class="form-label">
          {{ t('PATIENT_CONSENTS.FORM.OBSERVATIONS_LABEL') }}
          <span class="text-slate-600">
            {{ t('PATIENT_CONSENTS.FORM.OBSERVATIONS_OPTIONAL') }}
          </span>
        </label>
        <input
          v-model="form.observations"
          type="text"
          :placeholder="t('PATIENT_CONSENTS.FORM.OBSERVATIONS_PLACEHOLDER')"
          class="form-input"
        />
      </div>

      <div class="form-group">
        <div class="flex items-center justify-between mb-1.5">
          <label class="form-label">
            {{ t('PATIENT_CONSENTS.FORM.BODY_LABEL') }}
            <span class="text-slate-600 font-normal ml-1">
              {{ t('PATIENT_CONSENTS.FORM.BODY_HINT') }}
            </span>
          </label>
          <span v-if="form.body" class="text-xs text-slate-600">
            {{
              t('PATIENT_CONSENTS.FORM.BODY_CHARS', { count: form.body.length })
            }}
          </span>
        </div>
        <textarea
          v-model="form.body"
          rows="20"
          :placeholder="t('PATIENT_CONSENTS.FORM.BODY_PLACEHOLDER')"
          class="form-input font-mono leading-relaxed resize-y"
          style="min-height: 400px"
        />
      </div>

      <div class="flex items-center justify-between pt-2 border-t border-white/5">
        <p class="text-xs text-slate-500 flex items-center gap-1.5">
          <i class="i-lucide-info w-3 h-3" />
          {{ t('PATIENT_CONSENTS.FORM.FOOTER_PREFIX') }}
          <strong class="text-amber-400">
            {{ t('PATIENT_CONSENTS.FORM.FOOTER_PENDING') }}
          </strong>
          {{ t('PATIENT_CONSENTS.FORM.FOOTER_SUFFIX') }}
        </p>
        <div class="flex gap-3">
          <BeclinicButton
            variant="ghost"
            color="slate"
            :label="t('PATIENT_CONSENTS.FORM.CANCEL')"
            @click="emit('close')"
          />
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-file-plus"
            :label="
              loading
                ? t('PATIENT_CONSENTS.FORM.CREATING')
                : t('PATIENT_CONSENTS.FORM.CREATE')
            "
            :is-loading="loading"
            :disabled="loading || !form.consent_type"
            @click="handleCreate"
          />
        </div>
      </div>
    </div>
  </div>
</template>
