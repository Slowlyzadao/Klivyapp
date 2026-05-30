<script setup>
// Botão primitivo da toolbar do TipTap. Suporta estado "active" (quando o
// mark/node está aplicado no cursor) e ícone Lucide.
//
// IMPORTANTE: Tailwind faz scan ESTÁTICO das classes — concatenar dinamicamente
// (`i-lucide-${icon}`) impede a geração do CSS do glifo. Por isso o mapa
// abaixo lista LITERALMENTE cada classe possível. Adicionou ícone novo na
// toolbar? Lembra de declarar aqui.

import { computed } from 'vue';

const props = defineProps({
  icon: { type: String, required: true },
  active: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  title: { type: String, default: '' },
});

defineEmits(['click']);

// Mapa de ícones usados pela EditorToolbar. Cada entrada precisa estar
// presente como string literal pra Tailwind detectar e emitir o CSS do
// background-image SVG via @egoist/tailwindcss-icons.
//
// Strings literais usadas pelo Tailwind scanner (precisam aparecer por extenso):
//   i-lucide-undo-2 i-lucide-redo-2
//   i-lucide-bold i-lucide-italic i-lucide-underline i-lucide-strikethrough
//   i-lucide-superscript i-lucide-subscript
//   i-lucide-heading-1 i-lucide-heading-2 i-lucide-heading-3
//   i-lucide-list i-lucide-list-ordered
//   i-lucide-align-left i-lucide-align-center i-lucide-align-right i-lucide-align-justify
//   i-lucide-link i-lucide-unlink i-lucide-table i-lucide-image i-lucide-braces
//   i-lucide-quote i-lucide-minus i-lucide-remove-formatting
//   i-lucide-indent-increase i-lucide-indent-decrease i-lucide-scissors-line-dashed
const ICON_CLASSES = {
  'undo-2':              'i-lucide-undo-2',
  'redo-2':              'i-lucide-redo-2',
  'bold':                'i-lucide-bold',
  'italic':              'i-lucide-italic',
  'underline':           'i-lucide-underline',
  'strikethrough':       'i-lucide-strikethrough',
  'superscript':         'i-lucide-superscript',
  'subscript':           'i-lucide-subscript',
  'heading-1':           'i-lucide-heading-1',
  'heading-2':           'i-lucide-heading-2',
  'heading-3':           'i-lucide-heading-3',
  'list':                'i-lucide-list',
  'list-ordered':        'i-lucide-list-ordered',
  'align-left':          'i-lucide-align-left',
  'align-center':        'i-lucide-align-center',
  'align-right':         'i-lucide-align-right',
  'align-justify':       'i-lucide-align-justify',
  'link':                'i-lucide-link',
  'unlink':              'i-lucide-unlink',
  'table':               'i-lucide-table',
  'image':               'i-lucide-image',
  'braces':              'i-lucide-braces',
  'quote':               'i-lucide-quote',
  'minus':               'i-lucide-minus',
  'remove-formatting':   'i-lucide-remove-formatting',
  'indent-increase':     'i-lucide-indent-increase',
  'indent-decrease':     'i-lucide-indent-decrease',
  'scissors-line-dashed':'i-lucide-scissors-line-dashed',
};

const iconClass = computed(() => ICON_CLASSES[props.icon] || '');
</script>

<template>
  <button
    type="button"
    class="editor-toolbar__btn"
    :class="{ 'editor-toolbar__btn--active': active }"
    :disabled="disabled"
    :title="title"
    :aria-label="title"
    :aria-pressed="active"
    @click="$emit('click')"
  >
    <span :class="iconClass" />
  </button>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/toolbar';
</style>
