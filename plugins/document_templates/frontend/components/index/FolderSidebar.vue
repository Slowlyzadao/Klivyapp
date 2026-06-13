<script setup>
// Sidebar de organização — card branco com:
//   • "Todos os modelos" (value=null)
//   • pastas da clínica (value=id, deletáveis, aceitam drop)
//   • "Arquivados" (value='archived', view especial)
//
// Todos os itens usam o MESMO componente FolderItem (DRY + CSS num lugar só).

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FolderItem from './FolderItem.vue';

const props = defineProps({
  folders: { type: Array, default: () => [] },
  templates: { type: Array, default: () => [] },
  selectedFolderId: { type: [Number, String, null], default: null },
  archivedCount: { type: Number, default: 0 },
});

const emit = defineEmits([
  'select',
  'click-new-folder',
  'drop-template',
  'delete-folder',
]);

const { t } = useI18n();

// Conta só os ativos/draft (não-arquivados) por pasta.
const liveTemplates = computed(() =>
  props.templates.filter(t => t.status !== 'archived'),
);

const totalActive = computed(() => liveTemplates.value.length);

const countForFolder = (folderId) =>
  liveTemplates.value.filter(t => t.folder_id === folderId).length;
</script>

<template>
  <aside class="folder-sidebar">
    <div class="folder-sidebar__card">
      <header class="folder-sidebar__header">
        <h3 class="folder-sidebar__label">
          {{ t('DOCUMENT_TEMPLATES.SIDEBAR.SECTION_TITLE') }}
        </h3>
        <button
          type="button"
          class="folder-sidebar__icon-btn"
          :title="t('DOCUMENT_TEMPLATES.SIDEBAR.NEW_FOLDER')"
          :aria-label="t('DOCUMENT_TEMPLATES.SIDEBAR.NEW_FOLDER')"
          @click="emit('click-new-folder')"
        >
          <span class="i-lucide-plus" />
        </button>
      </header>

      <div class="folder-sidebar__list">
        <FolderItem
          :label="t('DOCUMENT_TEMPLATES.SIDEBAR.ALL')"
          icon="i-lucide-folder"
          :value="null"
          :active="selectedFolderId === null"
          :count="totalActive"
          @select="emit('select', $event)"
          @drop-template="emit('drop-template', $event)"
        />

        <FolderItem
          v-for="folder in folders"
          :key="folder.id"
          :label="folder.name"
          icon="i-lucide-folder"
          :value="folder.id"
          :active="selectedFolderId === folder.id"
          :count="countForFolder(folder.id)"
          deletable
          :delete-title="t('DOCUMENT_TEMPLATES.SIDEBAR.DELETE_FOLDER')"
          @select="emit('select', $event)"
          @delete="emit('delete-folder', folder)"
          @drop-template="emit('drop-template', $event)"
        />

        <div class="folder-sidebar__divider" />

        <FolderItem
          :label="t('DOCUMENT_TEMPLATES.SIDEBAR.ARCHIVED')"
          icon="i-lucide-archive"
          value="archived"
          :active="selectedFolderId === 'archived'"
          :count="archivedCount"
          :droppable="false"
          @select="emit('select', $event)"
        />
      </div>
    </div>
  </aside>
</template>

<style lang="scss" scoped>
@use '../../styles/index/folder-sidebar';
</style>
