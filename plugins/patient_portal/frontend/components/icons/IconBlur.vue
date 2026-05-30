<script setup>
// Ícone de desfoque de fundo (background blur). Inspirado no Google Meet:
// silhueta de pessoa em primeiro plano + pontinhos atrás representando o
// fundo desfocado. Usa stroke (consistente com os outros ícones do portal)
// pra silhueta e fill pros pontos do fundo.
import BaseIcon from './BaseIcon.vue';
</script>

<template>
  <BaseIcon v-bind="$attrs">
    <!-- Cabeça da pessoa em primeiro plano. -->
    <circle cx="12" cy="8" r="3" />
    <!-- Ombros/corpo. -->
    <path d="M5 21v-1a7 7 0 0 1 14 0v1" />
    <!-- Pontinhos de fundo (representam blur) — usam fill em vez de stroke
         pra parecerem "partículas" e não círculos vazios. -->
    <circle cx="3" cy="6" r="0.8" fill="currentColor" stroke="none" />
    <circle cx="21" cy="6" r="0.8" fill="currentColor" stroke="none" />
    <circle cx="6" cy="3" r="0.8" fill="currentColor" stroke="none" />
    <circle cx="18" cy="3" r="0.8" fill="currentColor" stroke="none" />
    <circle cx="12" cy="2" r="0.8" fill="currentColor" stroke="none" />
  </BaseIcon>
</template>
