<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import DocumentTemplatesAPI from '@plugins/patients/frontend/api/patients/documentTemplates';
import {
  DOC_TYPE_LABELS,
  DOC_TYPE_OPTIONS,
  FREE_CONTENT_TYPES,
  blankDocForm,
} from '@plugins/patients/frontend/constants/documents';
import { useDocumentTemplatePicker } from '@plugins/patients/frontend/features/patient-record/composables/useDocumentTemplatePicker';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'generate']);

const { t } = useI18n();

const form = ref(blankDocForm());

// ── Ponte com o editor de modelos (family clínica) ──────────────────────
// Quando um modelo é escolhido, o conteúdo vem do template (Grover) e os
// campos manuais de tipo somem. Sem modelo → fluxo manual legado intacto.
const templateId = ref('');
const { hasTemplates, fetchTemplates, findTemplate, buildOptions } =
  useDocumentTemplatePicker('clinical');

const usingTemplate = computed(() => Boolean(templateId.value));
const templateOptions = computed(() =>
  buildOptions(t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_NONE'))
);

// ── Campos de preenchimento do modelo (variáveis input.*) ───────────────
// Ao escolher um modelo, buscamos o content_json e descobrimos quais campos
// `input.*` ele usa (CID, Dias de afastamento, etc.) — dados de instância que
// não vêm do cadastro. Renderizamos um campo pra cada e enviamos em `inputs`.
const inputFields = ref([]);
const inputs = reactive({});
const loadingFields = ref(false);

const resetInputs = () => {
  inputFields.value = [];
  Object.keys(inputs).forEach(k => delete inputs[k]);
};

const collectInputVars = (node, acc, seen) => {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'variable') {
    const key = node.attrs?.key;
    if (key && key.startsWith('input.') && !seen.has(key)) {
      seen.add(key);
      acc.push({ key, label: node.attrs.label || key });
    }
  }
  if (Array.isArray(node.content)) {
    node.content.forEach(child => collectInputVars(child, acc, seen));
  }
};

const onTemplateChange = async () => {
  resetInputs();
  const id = templateId.value;
  const tpl = findTemplate(id);
  if (tpl && !form.value.title) form.value.title = tpl.name;
  if (!id) return;

  loadingFields.value = true;
  try {
    const res = await DocumentTemplatesAPI.show(id);
    const content = res.data?.data?.content_json || res.data?.content_json;
    const acc = [];
    collectInputVars(content, acc, new Set());
    inputFields.value = acc;
    acc.forEach(f => {
      inputs[f.key] = '';
    });
  } catch (e) {
    inputFields.value = [];
  } finally {
    loadingFields.value = false;
  }
};

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      form.value = blankDocForm();
      templateId.value = '';
      resetInputs();
      // force: relê a lista a cada abertura — modelos recém-criados/editados
      // aparecem sem precisar recarregar a página. O conteúdo (campos de
      // preenchimento) já é buscado fresco por seleção em onTemplateChange.
      fetchTemplates({ force: true });
    }
  }
);

const isFreeContent = computed(() =>
  FREE_CONTENT_TYPES.includes(form.value.document_type)
);

const handleGenerate = () => {
  const tpl = usingTemplate.value ? findTemplate(templateId.value) : null;
  emit('generate', {
    ...form.value,
    document_template_id: templateId.value || null,
    title: form.value.title || tpl?.name || form.value.title,
    // Campos de preenchimento do modelo (só quando usando modelo com inputs).
    inputs:
      usingTemplate.value && inputFields.value.length ? { ...inputs } : undefined,
  });
};

onMounted(() => {
  if (props.open) fetchTemplates();
});
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
        <div v-if="hasTemplates" class="form-group">
          <label class="form-label">
            {{ t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_LABEL') }}
            <span class="text-slate-600">
              {{ t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_OPTIONAL') }}
            </span>
          </label>
          <FormSelect
            v-model="templateId"
            :options="templateOptions"
            :placeholder="t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_PLACEHOLDER')"
            auto-searchable
            @update:model-value="onTemplateChange"
          />
          <p
            v-if="usingTemplate"
            class="text-xs text-slate-500 mt-1.5 leading-snug flex items-start gap-1.5"
          >
            <i class="i-lucide-info w-3 h-3 mt-0.5 flex-shrink-0" />
            {{ t('PATIENT_DOCUMENTS.MODAL.TEMPLATE_HINT') }}
          </p>
        </div>

        <!-- Campos de preenchimento do modelo (variáveis input.*). -->
        <div
          v-if="usingTemplate && inputFields.length"
          class="form-group"
        >
          <label class="form-label">
            {{ t('PATIENT_DOCUMENTS.MODAL.INPUT_FIELDS_LABEL') }}
          </label>
          <div class="reg-field-grid-2">
            <div
              v-for="f in inputFields"
              :key="f.key"
              class="form-group"
            >
              <label class="form-label">{{ f.label }}</label>
              <input
                v-model="inputs[f.key]"
                type="text"
                class="form-input"
                :placeholder="f.label"
              />
            </div>
          </div>
        </div>

        <div v-if="!usingTemplate" class="form-group">
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

        <template v-if="!usingTemplate && form.document_type === 'atestado'">
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

        <template v-if="!usingTemplate && form.document_type === 'receita'">
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

        <template v-if="!usingTemplate && form.document_type === 'pedido_exame'">
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

        <template v-if="!usingTemplate && form.document_type === 'encaminhamento'">
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

        <template v-if="!usingTemplate && isFreeContent">
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
