<script setup>
// NodeView Vue do nó `variable` no TipTap. Renderiza o chip não-editável
// dentro do editor — texto puro do label, ícone, badge de cor.
//
// `node.attrs` vem do schema definido em VariableExtension.js
// (`key`, `label`, `fallback`, `format`).

import { computed } from 'vue';
import { NodeViewWrapper, nodeViewProps } from '@tiptap/vue-3';

const props = defineProps(nodeViewProps);

const display = computed(() =>
  props.node.attrs.label || props.node.attrs.key || '???'
);
</script>

<template>
  <NodeViewWrapper
    as="span"
    class="tiptap-variable-chip"
    :class="{ 'tiptap-variable-chip--selected': selected }"
    :data-key="node.attrs.key"
    :title="node.attrs.key"
  >
    <span class="i-lucide-braces tiptap-variable-chip__icon" />
    <span class="tiptap-variable-chip__label">{{ display }}</span>
  </NodeViewWrapper>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/variable-node';
</style>
