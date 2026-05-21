<script setup>
import BaseIcon from './BaseIcon.vue';
</script>

<template>
  <BaseIcon v-bind="$attrs">
    <rect x="9" y="2" width="6" height="12" rx="3" />
    <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
    <line x1="12" y1="19" x2="12" y2="22" />
  </BaseIcon>
</template>
