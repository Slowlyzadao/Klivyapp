<script setup>
import BaseIcon from './BaseIcon.vue';
</script>

<template>
  <BaseIcon v-bind="$attrs">
    <rect x="3" y="4" width="18" height="13" rx="2" />
    <path d="M8 21h8" />
    <path d="M12 17v4" />
    <path d="M12 14V8" />
    <path d="M9 10l3-3 3 3" />
  </BaseIcon>
</template>
