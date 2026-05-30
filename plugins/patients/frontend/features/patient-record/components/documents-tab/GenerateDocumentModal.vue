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
import { documentTemplatesApi } from '@plugins/document_templates/frontend/api/documentTemplates';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'generate']);

const { t } = useI18n();

const form = ref(blankDocForm());

// ── Templates do document-editor compatíveis com o tipo escolhido ──────────
// Quando o user troca o tipo de documento, recarregamos os templates da
// clínica + Klivy globais daquele tipo. Se há ≥ 1, mostramos o dropdown
// "Modelo" pra ele escolher (ou ficar no "Padrão" = Prawn legado).
const availableTemplates = ref([]);
const templatesLoading = ref(false);

const fetchTemplates = async docType => {
  if (!docType) {
    availableTemplates.value = [];
    return;
  }
  templatesLoading.value = true;
  try {
    const [own, klivy] = await Promise.all([
      documentTemplatesApi.list({ documentType: docType }),
      documentTemplatesApi.klivyLibrary({ documentType: docType }),
    ]);
    // Próprios primeiro (clínica conhece os deles); Klivy depois.
    availableTemplates.value = [
      ...(own?.data?.data || []),
      ...(klivy?.data?.data || []),
    ];
  } catch (_e) {
    availableTemplates.value = [];
  } finally {
    templatesLoading.value = false;
  }
};

const templateOptions = computed(() => [
  // Default: usa o Prawn legado quando o user não escolhe template.
  { value: null, label: t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_DEFAULT') },
  ...availableTemplates.value.map(tpl => ({
    value: tpl.id,
    label: tpl.is_klivy ? `${tpl.name} · Klivy` : tpl.name,
  })),
]);

const hasTemplates = computed(() => availableTemplates.value.length > 0);

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      form.value = blankDocForm();
      fetchTemplates(form.value.document_type);
    }
  }
);

watch(
  () => form.value.document_type,
  newType => {
    // Resetar seleção de template — um modelo de "atestado" não serve
    // pra "receita".
    form.value.document_template_id = null;
    fetchTemplates(newType);
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

        <!-- Dropdown "Modelo" — só aparece quando existem templates compatíveis
             com o tipo selecionado. Se não há, segue o caminho default (Prawn).
             Quando o user escolhe um template, o backend delega pro Grover. -->
        <div v-if="hasTemplates" class="form-group">
          <label class="form-label">
            {{ t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_LABEL') }}
            <span class="text-slate-600">
              {{ t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_OPTIONAL') }}
            </span>
          </label>
          <FormSelect
            v-model="form.document_template_id"
            :options="templateOptions"
            :placeholder="
              templatesLoading
                ? t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_LOADING')
                : t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_PLACEHOLDER')
            "
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
