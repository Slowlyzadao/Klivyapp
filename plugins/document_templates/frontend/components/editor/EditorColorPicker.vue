<script setup>
// Swatch-dropdown reutilizável pra cor de texto (mode='text') e realce/
// highlight (mode='highlight'). Gatilho é um glifo lucide solto (sem caixa)
// com uma faixa fina mostrando a cor atual — regra de ícones sem padding.
//
// text:      setColor / unsetColor (extensão Color já registrada)
// highlight: toggleHighlight({color}) / unsetHighlight (Highlight multicolor)

import { ref, computed } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  editor: { type: Object, required: true },
  mode: {
    type: String,
    required: true,
    validator: (v) => ['text', 'highlight'].includes(v),
  },
});

const { t } = useI18n();

const TEXT_SWATCHES = [
  '#111111', '#5f6368', '#003cc1', '#1552f1',
  '#d93025', '#188038', '#e8710a', '#8e24aa',
];
const HIGHLIGHT_SWATCHES = [
  '#fff176', '#ffd54f', '#a5d6a7', '#80deea',
  '#90caf9', '#f48fb1', '#ce93d8', '#e0e0e0',
];

const swatches = computed(() =>
  props.mode === 'text' ? TEXT_SWATCHES : HIGHLIGHT_SWATCHES,
);

const icon = computed(() =>
  props.mode === 'text' ? 'i-lucide-baseline' : 'i-lucide-highlighter',
);

const label = computed(() =>
  props.mode === 'text'
    ? t('DOCUMENT_TEMPLATES.EDITOR.TEXT_COLOR')
    : t('DOCUMENT_TEMPLATES.EDITOR.HIGHLIGHT'),
);

// Cor atual (pra pintar a faixa sob o ícone).
const currentColor = () => {
  if (props.mode === 'text') return props.editor.getAttributes('textStyle').color || '';
  return props.editor.getAttributes('highlight').color || '';
};

const open = ref(false);
const rootRef = ref(null);
onClickOutside(rootRef, () => { open.value = false; });

const apply = (color) => {
  const chain = props.editor.chain().focus();
  if (props.mode === 'text') chain.setColor(color).run();
  else chain.toggleHighlight({ color }).run();
  open.value = false;
};

const clear = () => {
  const chain = props.editor.chain().focus();
  if (props.mode === 'text') chain.unsetColor().run();
  else chain.unsetHighlight().run();
  open.value = false;
};
</script>

<template>
  <div ref="rootRef" class="color-picker">
    <button
      type="button"
      class="color-picker__trigger"
      :title="label"
      :aria-label="label"
      @click="open = !open"
    >
      <span :class="icon" class="color-picker__icon" />
      <span
        class="color-picker__bar"
        :style="{ background: currentColor() || 'transparent' }"
      />
    </button>

    <div v-if="open" class="color-picker__pop" role="menu">
      <button
        v-for="color in swatches"
        :key="color"
        type="button"
        class="color-picker__swatch"
        :style="{ background: color }"
        :title="color"
        @click="apply(color)"
      />
      <button
        type="button"
        class="color-picker__none"
        @click="clear"
      >
        <span class="i-lucide-ban color-picker__none-icon" />
        {{ t('DOCUMENT_TEMPLATES.EDITOR.COLOR_NONE') }}
      </button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/color-picker';
</style>
