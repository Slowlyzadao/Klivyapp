<script setup>
// Resumo executivo da teleconsulta (≤600 chars, gerado por IA — PRD §3.2).
// O backend ainda não popula o campo dedicado; caímos no `raw_markdown`
// truncado quando o summary não chega.
import { computed } from 'vue';

const MAX_LEN = 600;

const props = defineProps({
  summary: { type: String, default: '' },
  fallback: { type: String, default: '' },
});

const text = computed(() => {
  const value = (props.summary || props.fallback || '').trim();
  if (!value) return '';
  return value.length > MAX_LEN ? `${value.slice(0, MAX_LEN).trim()}…` : value;
});

const isEmpty = computed(() => text.value.length === 0);
</script>

<template>
  <section class="tcd-card">
    <h3 class="tcd-card__title">
      <i class="i-lucide-clipboard-list w-5 h-5 tcd-card__title-icon" />
      <span>Resumo da Teleconsulta</span>
    </h3>

    <p v-if="isEmpty" class="tcd-summary__empty">
      Resumo executivo ainda não disponível para esta teleconsulta.
    </p>
    <p v-else class="tcd-summary__text">{{ text }}</p>
  </section>
</template>
