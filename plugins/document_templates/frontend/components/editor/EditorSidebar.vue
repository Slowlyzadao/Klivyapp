<script setup>
// Painel lateral direito do editor — abas "Configurações" e "Variáveis".
//
// Configurações: nome, tipo de documento, pasta, papel, orientação.
// Variáveis: catálogo agrupado por categoria. Click insere no editor.
//
// Stateless quanto ao TipTap — emite eventos pro pai (TemplateEditor.vue).

import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { DOCUMENT_TYPE_LABELS } from '../../constants/documentTypes';
import { useVariableCatalog } from '../../composables/useVariableCatalog';
import VariablePickerMenu from './VariablePickerMenu.vue';

const props = defineProps({
  template: { type: Object, required: true },
  folders: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'update:settings',
  'insert-variable',
]);

const { t } = useI18n();
const activeTab = ref('settings');

const { variables } = useVariableCatalog();
const highlightedIndex = ref(0);

const typeOptions = computed(() =>
  Object.entries(DOCUMENT_TYPE_LABELS).map(([value, label]) => ({ value, label }))
);

const updateField = (field, value) => {
  emit('update:settings', { [field]: value });
};

const insertVariable = (variable) => {
  emit('insert-variable', variable);
};
</script>

<template>
  <aside class="editor-sidebar">
    <nav class="editor-sidebar__tabs">
      <button
        type="button"
        class="editor-sidebar__tab"
        :class="{ 'editor-sidebar__tab--active': activeTab === 'settings' }"
        @click="activeTab = 'settings'"
      >
        <span class="i-lucide-settings-2" />
        {{ t('DOCUMENT_TEMPLATES.EDITOR.TAB_SETTINGS') }}
      </button>
      <button
        type="button"
        class="editor-sidebar__tab"
        :class="{ 'editor-sidebar__tab--active': activeTab === 'variables' }"
        @click="activeTab = 'variables'"
      >
        <span class="i-lucide-braces" />
        {{ t('DOCUMENT_TEMPLATES.EDITOR.TAB_VARIABLES') }}
      </button>
    </nav>

    <div class="editor-sidebar__content">
      <section v-if="activeTab === 'settings'" class="form-stack">
        <label class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.NAME') }}</span>
          <input
            :value="template.name"
            type="text"
            class="form-stack__input"
            @input="updateField('name', $event.target.value)"
          />
        </label>

        <label class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.DOCUMENT_TYPE') }}</span>
          <select
            :value="template.document_type"
            class="form-stack__input"
            @change="updateField('document_type', $event.target.value)"
          >
            <option v-for="opt in typeOptions" :key="opt.value" :value="opt.value">
              {{ opt.label }}
            </option>
          </select>
        </label>

        <label class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.FOLDER') }}</span>
          <select
            :value="template.folder_id || ''"
            class="form-stack__input"
            @change="updateField('folder_id', $event.target.value || null)"
          >
            <option value="">{{ t('DOCUMENT_TEMPLATES.FIELDS.NO_FOLDER') }}</option>
            <option v-for="f in folders" :key="f.id" :value="f.id">
              {{ f.name }}
            </option>
          </select>
        </label>

        <label class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.PAPER_SIZE') }}</span>
          <select
            :value="template.paper_size"
            class="form-stack__input"
            @change="updateField('paper_size', $event.target.value)"
          >
            <option value="A4">A4</option>
            <option value="Letter">Letter</option>
            <option value="A5">A5</option>
          </select>
        </label>

        <label class="form-stack__field">
          <span class="form-stack__label">{{ t('DOCUMENT_TEMPLATES.FIELDS.ORIENTATION') }}</span>
          <select
            :value="template.orientation"
            class="form-stack__input"
            @change="updateField('orientation', $event.target.value)"
          >
            <option value="portrait">{{ t('DOCUMENT_TEMPLATES.FIELDS.PORTRAIT') }}</option>
            <option value="landscape">{{ t('DOCUMENT_TEMPLATES.FIELDS.LANDSCAPE') }}</option>
          </select>
        </label>
      </section>

      <section v-else class="editor-sidebar__variables">
        <VariablePickerMenu
          :items="variables"
          :show-search="true"
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
