<script setup>
// Menu contextual de tabela — só aparece quando o cursor está numa tabela
// (controlado pelo pai via v-if isActive('table')). Mantém a toolbar limpa
// agrupando todas as ações de tabela num dropdown. Todos os comandos vêm do
// @tiptap/extension-table já instalado.

import { ref } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  editor: { type: Object, required: true },
});

const { t } = useI18n();

const open = ref(false);
const rootRef = ref(null);
onClickOutside(rootRef, () => { open.value = false; });

const run = (fn) => {
  fn(props.editor.chain().focus()).run();
  open.value = false;
};

const items = [
  { key: 'ADD_ROW_ABOVE', icon: 'i-lucide-between-horizontal-start', cmd: (c) => c.addRowBefore() },
  { key: 'ADD_ROW_BELOW', icon: 'i-lucide-between-horizontal-end', cmd: (c) => c.addRowAfter() },
  { key: 'ADD_COL_BEFORE', icon: 'i-lucide-between-vertical-start', cmd: (c) => c.addColumnBefore() },
  { key: 'ADD_COL_AFTER', icon: 'i-lucide-between-vertical-end', cmd: (c) => c.addColumnAfter() },
  { key: 'TOGGLE_HEADER_ROW', icon: 'i-lucide-table-rows-split', cmd: (c) => c.toggleHeaderRow() },
  { key: 'DELETE_ROW', icon: 'i-lucide-trash-2', cmd: (c) => c.deleteRow(), danger: true },
  { key: 'DELETE_COL', icon: 'i-lucide-trash-2', cmd: (c) => c.deleteColumn(), danger: true },
  { key: 'DELETE_TABLE', icon: 'i-lucide-trash-2', cmd: (c) => c.deleteTable(), danger: true },
];
</script>

<template>
  <div ref="rootRef" class="table-menu">
    <button
      type="button"
      class="editor-toolbar__btn editor-toolbar__btn--active"
      :title="t('DOCUMENT_TEMPLATES.EDITOR.TABLE_MENU')"
      :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.TABLE_MENU')"
      @click="open = !open"
    >
      <span class="i-lucide-table-properties" />
    </button>

    <div v-if="open" class="table-menu__pop" role="menu">
      <button
        v-for="item in items"
        :key="item.key"
        type="button"
        class="table-menu__item"
        :class="{ 'table-menu__item--danger': item.danger }"
        @click="run(item.cmd)"
      >
        <span :class="item.icon" class="table-menu__icon" />
        {{ t(`DOCUMENT_TEMPLATES.EDITOR.${item.key}`) }}
      </button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/table-menu';
</style>
