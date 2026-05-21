<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  DOC_TYPE_LABELS,
  DOC_TYPE_OPTIONS,
  FREE_CONTENT_TYPES,
  blankDocForm,
} from '@plugins/patients/frontend/constants/documents';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'generate']);

const { t } = useI18n();

const form = ref(blankDocForm());

watch(
  () => props.open,
  isOpen => {
    if (isOpen) form.value = blankDocForm();
  }
);

const isFreeContent = computed(() =>
  FREE_CONTENT_TYPES.includes(form.value.document_type)
);

const handleGenerate = () => {
  emit('generate', { ...form.value });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md"
  >
    <div class="docs-modal">
      <div class="docs-modal-header">
        <div class="flex items-center gap-3">
          <div class="docs-modal-icon">
            <i class="i-lucide-file-plus w-4 h-4" />
          </div>
          <div>
            <h4 class="text-base font-semibold text-slate-100">
              {{ t('PATIENT_DOCUMENTS.MODAL.TITLE') }}
            </h4>
            <p class="text-xs text-slate-500 mt-0.5">
              {{ t('PATIENT_DOCUMENTS.MODAL.SUBTITLE') }}
            </p>
          </div>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="docs-modal-body">
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_DOCUMENTS.MODAL.TYPE_LABEL') }}
            <span class="reg-required">*</span>
          </label>
          <FormSelect
            v-model="form.document_type"
            :options="DOC_TYPE_OPTIONS"
            :placeholder="t('PATIENT_DOCUMENTS.MODAL.TYPE_PLACEHOLDER')"
            auto-searchable
          />
        </div>

        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_DOCUMENTS.MODAL.DOCUMENT_TITLE_LABEL') }}
            <span class="text-slate-600">
              {{ t('PATIENT_DOCUMENTS.MODAL.DOCUMENT_TITLE_OPTIONAL') }}
            </span>
          </label>
          <input
            v-model="form.title"
            type="text"
            :placeholder="DOC_TYPE_LABELS[form.document_type]"
            class="form-input"
          />
        </div>

        <template v-if="form.document_type === 'atestado'">
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_DOCUMENTS.MODAL.ATESTADO.CID') }}
              </label>
              <input
                v-model="form.cid"
                type="text"
                :placeholder="t('PATIENT_DOCUMENTS.MODAL.ATESTADO.CID_PLACEHOLDER')"
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_DOCUMENTS.MODAL.ATESTADO.DAYS') }}
              </label>
              <input
                v-model="form.dias_afastamento"
                type="number"
                min="1"
                :placeholder="t('PATIENT_DOCUMENTS.MODAL.ATESTADO.DAYS_PLACEHOLDER')"
                class="form-input"
              />
            </div>
          </div>
        </template>

        <template v-if="form.document_type === 'receita'">
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_DOCUMENTS.MODAL.RECEITA.MEDICATIONS') }}
            </label>
            <textarea
              v-model="form.medicamentos"
              rows="3"
              :placeholder="
                t('PATIENT_DOCUMENTS.MODAL.RECEITA.MEDICATIONS_PLACEHOLDER')
              "
              class="form-input"
            />
          </div>
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_DOCUMENTS.MODAL.RECEITA.DOSAGE') }}
            </label>
            <textarea
              v-model="form.posologia"
              rows="2"
              :placeholder="t('PATIENT_DOCUMENTS.MODAL.RECEITA.DOSAGE_PLACEHOLDER')"
              class="form-input"
            />
          </div>
        </template>

        <template v-if="form.document_type === 'pedido_exame'">
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_DOCUMENTS.MODAL.EXAM.EXAMS_REQUESTED') }}
            </label>
            <textarea
              v-model="form.exames_solicitados"
              rows="3"
              :placeholder="t('PATIENT_DOCUMENTS.MODAL.EXAM.EXAMS_PLACEHOLDER')"
              class="form-input"
            />
          </div>
        </template>

        <template v-if="form.document_type === 'encaminhamento'">
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_DOCUMENTS.MODAL.REFERRAL.TO') }}
              </label>
              <input
                v-model="form.encaminhado_para"
                type="text"
                :placeholder="t('PATIENT_DOCUMENTS.MODAL.REFERRAL.TO_PLACEHOLDER')"
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label class="form-label">
                {{ t('PATIENT_DOCUMENTS.MODAL.REFERRAL.SPECIALTY') }}
              </label>
              <input
                v-model="form.especialidade"
                type="text"
                :placeholder="
                  t('PATIENT_DOCUMENTS.MODAL.REFERRAL.SPECIALTY_PLACEHOLDER')
                "
                class="form-input"
              />
            </div>
          </div>
        </template>

        <template v-if="isFreeContent">
          <div class="form-group">
            <label class="form-label">
              {{ t('PATIENT_DOCUMENTS.MODAL.FREE_CONTENT_LABEL') }}
            </label>
            <textarea
              v-model="form.conteudo_livre"
              rows="5"
              :placeholder="t('PATIENT_DOCUMENTS.MODAL.FREE_CONTENT_PLACEHOLDER')"
              class="form-input"
            />
          </div>
        </template>

        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_DOCUMENTS.MODAL.OBSERVATIONS_LABEL') }}
          </label>
          <textarea
            v-model="form.observacoes"
            rows="2"
            :placeholder="t('PATIENT_DOCUMENTS.MODAL.OBSERVATIONS_PLACEHOLDER')"
            class="form-input"
          />
        </div>
      </div>

      <div class="docs-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_DOCUMENTS.MODAL.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-file-plus"
          :label="
            loading
              ? t('PATIENT_DOCUMENTS.MODAL.GENERATING')
              : t('PATIENT_DOCUMENTS.MODAL.GENERATE')
          "
          :is-loading="loading"
          :disabled="loading"
          @click="handleGenerate"
        />
      </div>
    </div>
  </div>
</template>
