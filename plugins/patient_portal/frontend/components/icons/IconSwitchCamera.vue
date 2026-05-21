<script setup>
import BaseIcon from './BaseIcon.vue';
</script>

<template>
  <BaseIcon v-bind="$attrs">
    <!-- Corpo da câmera -->
    <path
      d="M3 7h3l2-3h8l2 3h3a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1z"
    />
    <!-- Setas circulares indicando "trocar" -->
    <path d="M15 13a3 3 0 1 1-3-3" />
    <path d="M15 9v3h-3" />
  </BaseIcon>
</template>
