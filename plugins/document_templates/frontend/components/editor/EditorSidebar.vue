<script setup>
// Painel lateral direito do editor — abas "Configurações" e "Variáveis".
//
// Configurações: nome, tipo de documento, pasta, papel, orientação.
// Variáveis: catálogo agrupado por categoria. Click insere no editor.
//
// Stateless quanto ao TipTap — emite eventos pro pai (TemplateEditor.vue).

import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  CLINICAL_TYPE_LABELS,
  CONSENT_TYPE_LABELS,
  isConsent,
} from '../../constants/documentTypes';
import { useVariableCatalog } from '../../composables/useVariableCatalog';
import VariablePickerMenu from './VariablePickerMenu.vue';
import Tabs from 'dashboard/components/ui/Tabs/Tabs.vue';
import TabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';

const props = defineProps({
  template: { type: Object, required: true },
  folders: { type: Array, default: () => [] },
  // Mapa { chave: valor } resolvido do paciente selecionado (preview ao vivo).
  // Repassado ao VariablePickerMenu pra mostrar os dados reais por variável.
  previewValues: { type: Object, default: () => ({}) },
  selectedPatientId: { type: [String, Number], default: '' },
});

const emit = defineEmits([
  'update:settings',
  'insert-variable',
]);

const { t } = useI18n();
const activeTab = ref('settings');

// Tabs do Chatwoot trabalham com índice numérico; mapeamos pro nome da aba.
const TAB_KEYS = ['settings', 'variables'];
const activeTabIndex = computed({
  get: () => Math.max(0, TAB_KEYS.indexOf(activeTab.value)),
  set: i => {
    activeTab.value = TAB_KEYS[i] || 'settings';
  },
});

const { variables } = useVariableCatalog();
const highlightedIndex = ref(0);

// Tipo ESCOPADO À FAMÍLIA do modelo: consentimento só troca entre
// consentimentos, clínico só entre clínicos. Evita mover o modelo de aba
// (Documentos × Consentimentos) e quebrar a geração ao cruzar família.
const typeOptions = computed(() => {
  const map = isConsent(props.template.document_type)
    ? CONSENT_TYPE_LABELS
    : CLINICAL_TYPE_LABELS;
  return Object.entries(map).map(([value, label]) => ({ value, label }));
});

const folderOptions = computed(() => [
  { value: '', label: t('DOCUMENT_TEMPLATES.FIELDS.NO_FOLDER') },
  ...props.folders.map(f => ({ value: f.id, label: f.name })),
]);

const paperOptions = [
  { value: 'A4', label: 'A4' },
  { value: 'Letter', label: 'Letter' },
  { value: 'A5', label: 'A5' },
];

const orientationOptions = computed(() => [
  {
    value: 'portrait',
    label: t('DOCUMENT_TEMPLATES.FIELDS.PORTRAIT'),
    icon: 'i-lucide-rectangle-vertical',
  },
  {
    value: 'landscape',
    label: t('DOCUMENT_TEMPLATES.FIELDS.LANDSCAPE'),
    icon: 'i-lucide-rectangle-horizontal',
  },
]);

const updateField = (field, value) => {
  emit('update:settings', { [field]: value });
};

const insertVariable = (variable) => {
  emit('insert-variable', variable);
};
</script>

<template>
  <aside class="editor-sidebar">
    <Tabs
      :index="activeTabIndex"
      @change="activeTabIndex = $event"
    >
      <TabsItem
        :index="0"
        :name="t('DOCUMENT_TEMPLATES.EDITOR.TAB_SETTINGS')"
        :show-badge="false"
      />
      <TabsItem
        :index="1"
        :name="t('DOCUMENT_TEMPLATES.EDITOR.TAB_VARIABLES')"
        :show-badge="false"
      />
    </Tabs>

    <div
      class="editor-sidebar__content"
      :class="{ 'editor-sidebar__content--flush': activeTab === 'variables' }"
    >
      <section v-if="activeTab === 'settings'" class="form-stack">
        <label class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.NAME') }}</span>
          <input
            :value="template.name"
            type="text"
            class="form-stack__input reset-base"
            @input="updateField('name', $event.target.value)"
          />
        </label>

        <div class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.DOCUMENT_TYPE') }}</span>
          <FormSelect
            :model-value="template.document_type"
            :options="typeOptions"
            auto-searchable
            @update:model-value="updateField('document_type', $event)"
          />
        </div>

        <div class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.FOLDER') }}</span>
          <FormSelect
            :model-value="template.folder_id || ''"
            :options="folderOptions"
            @update:model-value="updateField('folder_id', $event || null)"
          />
        </div>

        <div class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.PAPER_SIZE') }}</span>
          <FormSelect
            :model-value="template.paper_size"
            :options="paperOptions"
            @update:model-value="updateField('paper_size', $event)"
          />
        </div>

        <div class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.ORIENTATION') }}</span>
          <FormSelect
            :model-value="template.orientation"
            :options="orientationOptions"
            @update:model-value="updateField('orientation', $event)"
          >
            <template #option="{ option }">
              <i :class="[option.icon, 'editor-sidebar__opt-icon']" />
              {{ option.label }}
            </template>
            <template #selected="{ option }">
              <template v-if="option">
                <i :class="[option.icon, 'editor-sidebar__opt-icon']" />
                {{ option.label }}
              </template>
            </template>
          </FormSelect>
        </div>
      </section>

      <section v-else class="editor-sidebar__variables">
        <VariablePickerMenu
          :items="variables"
          :show-search="true"
          :preview-values="previewValues"
          :selected-patient-id="selectedPatientId"
          v-model:highlighted-index="highlightedIndex"
          @select="insertVariable"
        />
      </section>
    </div>
  </aside>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/sidebar';
@use '../../styles/modals/form-stack';
</style>
