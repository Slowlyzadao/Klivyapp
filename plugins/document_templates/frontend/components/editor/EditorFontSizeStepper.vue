<script setup>
// Controle de tamanho de fonte estilo Google Docs: [−][campo numérico][+].
// Envolve a extensão FontSize (setFontSize/unsetFontSize). Permite digitar
// qualquer valor (clamp 6..96) ou clicar nos steppers. Ícones soltos.

import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  editor: { type: Object, required: true },
});

const { t } = useI18n();

const MIN = 6;
const MAX = 96;
const DEFAULT = 14; // base do parágrafo (.ProseMirror font-size)

const local = ref(String(DEFAULT));

// Lê o tamanho atual do cursor (fontSize do textStyle) — re-sincroniza o
// campo conforme o cursor anda. Sem override explícito, mostra o base.
const readCurrent = () => {
  const raw = props.editor.getAttributes('textStyle').fontSize;
  if (!raw) return DEFAULT;
  const n = parseInt(String(raw), 10);
  return Number.isFinite(n) ? n : DEFAULT;
};

// Mantém o campo sincronizado a cada transação do editor.
watch(
  () => readCurrent(),
  (val) => { local.value = String(val); },
  { immediate: true },
);

const clamp = (n) => Math.min(MAX, Math.max(MIN, n));

const applySize = (n) => {
  const size = clamp(n);
  local.value = String(size);
  props.editor.chain().focus().setFontSize(`${size}px`).run();
};

const onInputCommit = () => {
  const n = parseInt(local.value, 10);
  if (Number.isFinite(n)) applySize(n);
  else local.value = String(readCurrent());
};

const step = (delta) => applySize(readCurrent() + delta);
</script>

<template>
  <div class="font-stepper">
    <button
      type="button"
      class="font-stepper__btn"
      :title="t('DOCUMENT_TEMPLATES.EDITOR.FONT_SIZE_DECREASE')"
      :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.FONT_SIZE_DECREASE')"
      @click="step(-1)"
    >
      <span class="i-lucide-minus" />
    </button>
    <input
      v-model="local"
      type="text"
      inputmode="numeric"
      size="2"
      maxlength="3"
      class="font-stepper__input reset-base"
      :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.FONT_SIZE')"
      @keydown.enter.prevent="onInputCommit"
      @blur="onInputCommit"
    />
    <button
      type="button"
      class="font-stepper__btn"
      :title="t('DOCUMENT_TEMPLATES.EDITOR.FONT_SIZE_INCREASE')"
      :aria-label="t('DOCUMENT_TEMPLATES.EDITOR.FONT_SIZE_INCREASE')"
      @click="step(1)"
    >
      <span class="i-lucide-plus" />
    </button>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/font-stepper';
</style>
