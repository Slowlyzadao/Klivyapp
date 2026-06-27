<script setup>
// Canvas A4 simulado — fundo branco com sombra, padding interno simulando
// margens. Recebe o conteúdo via slot pra desacoplar do TipTap (também usado
// em previews futuros).

import { computed } from 'vue';

const props = defineProps({
  paperSize: {
    type: String,
    default: 'A4',
    validator: (v) => ['A4', 'Letter', 'A5'].includes(v),
  },
  orientation: {
    type: String,
    default: 'portrait',
    validator: (v) => ['portrait', 'landscape'].includes(v),
  },
});

const dimensionClass = computed(() =>
  `paper-container--${props.paperSize.toLowerCase()}-${props.orientation}`
);
</script>

<template>
  <div class="paper-container" :class="dimensionClass">
    <div class="paper-container__sheet">
      <slot />
    </div>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/paper-container';
</style>
