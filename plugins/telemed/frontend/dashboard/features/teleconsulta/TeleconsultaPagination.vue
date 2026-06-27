<script setup>
// Paginação numerada com prev/next e ellipsis. Sem CSS interno — estilos
// vivem em ../../../styles/teleconsulta-index.scss (.tc-pagination__*).
import { computed } from 'vue';

const props = defineProps({
  currentPage: { type: Number, required: true },
  totalPages:  { type: Number, required: true },
  disabled:    { type: Boolean, default: false },
});
const emit = defineEmits(['change']);

// Janela deslizante: mostra 1, ellipsis, vizinhos do atual, ellipsis,
// último. Para totais pequenos (≤7) mostra todos sem ellipsis.
const pages = computed(() => {
  const total = Math.max(1, props.totalPages);
  const current = Math.min(Math.max(1, props.currentPage), total);
  const items = [];
  if (total <= 7) {
    for (let i = 1; i <= total; i += 1) items.push(i);
    return items;
  }
  items.push(1);
  if (current > 3) items.push('…');
  const start = Math.max(2, current - 1);
  const end = Math.min(total - 1, current + 1);
  for (let i = start; i <= end; i += 1) items.push(i);
  if (current < total - 2) items.push('…');
  items.push(total);
  return items;
});

const canPrev = computed(() => !props.disabled && props.currentPage > 1);
const canNext = computed(() => !props.disabled && props.currentPage < props.totalPages);

const change = target => {
  if (props.disabled) return;
  const next = Math.min(Math.max(1, target), props.totalPages);
  if (next === props.currentPage) return;
  emit('change', next);
};
</script>

<template>
  <nav
    v-if="totalPages > 1"
    class="tc-pagination"
    role="navigation"
    aria-label="Paginação"
  >
    <button
      type="button"
      class="tc-pagination__btn"
      :disabled="!canPrev"
      aria-label="Página anterior"
      @click="change(currentPage - 1)"
    >
      <i class="i-lucide-chevron-left w-4 h-4" />
    </button>

    <template v-for="(item, idx) in pages" :key="`${item}-${idx}`">
      <span v-if="item === '…'" class="tc-pagination__ellipsis">…</span>
      <button
        v-else
        type="button"
        :class="['tc-pagination__btn', { 'is-active': item === currentPage }]"
        :aria-current="item === currentPage ? 'page' : undefined"
        :disabled="disabled"
        @click="change(item)"
      >
        {{ item }}
      </button>
    </template>

    <button
      type="button"
      class="tc-pagination__btn"
      :disabled="!canNext"
      aria-label="Próxima página"
      @click="change(currentPage + 1)"
    >
      <i class="i-lucide-chevron-right w-4 h-4" />
    </button>
  </nav>
</template>
