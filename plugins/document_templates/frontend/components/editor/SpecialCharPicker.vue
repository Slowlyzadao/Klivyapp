<script setup>
// Picker de caracteres especiais — glifos úteis em contratos/termos
// (parágrafo §, marca registrada, graus, frações, setas, etc). Insere
// unicode puro via insertContent (flui pelo render_text já escapado).
// Sem extensão TipTap, sem npm, sem mudança no renderer.

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

// Glifos curados pra documentos jurídicos/clínicos.
const CHARS = [
  '§', '¶', '©', '®', '™', '°', '′', '″',
  '×', '÷', '±', '≤', '≥', '≠', '–', '—',
  '“', '”', '‘', '’', '«', '»', '…', '•',
  '→', '⇒', '☐', '☑', '✓', '✗', '½', '¼',
];

const insert = (ch) => {
  props.editor.chain().focus().insertContent(ch).run();
  open.value = false;
};
</script>

<template>
  <div ref="rootRef" class="special-char">
    <button
      type="button"
      class="editor-toolbar__btn"
      :title="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_SPECIAL_CHAR')"
      :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.INSERT_SPECIAL_CHAR')"
      @click="open = !open"
    >
      <span class="i-lucide-omega" />
    </button>

    <div v-if="open" class="special-char__pop" role="menu">
      <button
        v-for="ch in CHARS"
        :key="ch"
        type="button"
        class="special-char__glyph"
        @click="insert(ch)"
      >
        {{ ch }}
      </button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/special-char';
</style>
