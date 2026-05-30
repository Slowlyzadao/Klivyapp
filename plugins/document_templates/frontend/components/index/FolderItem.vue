<script setup>
// Item da sidebar de organização. Value-based + reusável pra TODOS os itens:
// "Todos os modelos" (value=null), pastas reais (value=id) e "Arquivados"
// (value='archived'). Mantém o CSS num único lugar (evita o bug de estilo
// scoped que deixava o item inline sem formatação).
//
// • deletable → mostra botão de excluir no hover (só pastas reais)
// • droppable → aceita drop de TemplateCard pra mover entre pastas
//
// Emite: select(value), delete(value), drop-template({ templateId, folderId }).

import { ref } from 'vue';

const props = defineProps({
  label: { type: String, required: true },
  icon: { type: String, default: 'i-lucide-folder' },
  value: { type: [Number, String, null], default: null },
  active: { type: Boolean, default: false },
  count: { type: Number, default: 0 },
  deletable: { type: Boolean, default: false },
  droppable: { type: Boolean, default: true },
  deleteTitle: { type: String, default: '' },
});

const emit = defineEmits(['select', 'delete', 'drop-template']);

const MIME_TYPE = 'application/x-doc-template-id';
const isDropTarget = ref(false);

const onDragOver = (e) => {
  if (!props.droppable) return;
  if (e.dataTransfer.types.includes(MIME_TYPE) || e.dataTransfer.types.length === 0) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    isDropTarget.value = true;
  }
};

const onDragLeave = () => {
  isDropTarget.value = false;
};

const onDrop = (e) => {
  isDropTarget.value = false;
  if (!props.droppable) return;
  const templateId = Number(e.dataTransfer.getData(MIME_TYPE));
  if (!templateId) return;
  e.preventDefault();
  emit('drop-template', { templateId, folderId: props.value });
};

const onDelete = (e) => {
  e.stopPropagation();
  emit('delete', props.value);
};
</script>

<template>
  <div
    class="folder-item"
    :class="{
      'folder-item--active': active,
      'folder-item--drop-target': isDropTarget,
    }"
    role="button"
    tabindex="0"
    @click="emit('select', value)"
    @keydown.enter="emit('select', value)"
    @dragover="onDragOver"
    @dragleave="onDragLeave"
    @drop="onDrop"
  >
    <span :class="icon" class="folder-item__icon" />
    <span class="folder-item__name">{{ label }}</span>
    <span v-if="count > 0" class="folder-item__count">{{ count }}</span>
    <button
      v-if="deletable"
      type="button"
      class="folder-item__delete"
      :title="deleteTitle"
      :aria-label="deleteTitle"
      @click="onDelete"
    >
      <span class="i-lucide-trash-2" />
    </button>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/index/folder-item';
</style>
