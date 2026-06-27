<script setup>
// NodeView Vue do nó `variable` no TipTap.
//
// Chip não-editável (atom) com o label da variável ({{ Nome }}). O valor real
// só é resolvido no backend, na geração do PDF (Renderer/Resolver) — o editor
// mostra sempre o rótulo. (A pré-visualização dos valores reais vive na aba
// lateral "Variáveis", não na folha.)
//
// `node.attrs` vem do schema (VariableExtension.js): key/label/fallback/format.

import { nodeViewProps, NodeViewWrapper } from '@tiptap/vue-3';

const props = defineProps(nodeViewProps);

const label = () => props.node.attrs.label || props.node.attrs.key || '???';
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
    <span class="tiptap-variable-chip__label">{{ label() }}</span>
  </NodeViewWrapper>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/variable-node';
</style>
