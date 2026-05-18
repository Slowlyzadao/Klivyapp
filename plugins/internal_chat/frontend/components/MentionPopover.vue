<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  candidates: { type: Array, required: true },
  highlightedIndex: { type: Number, default: 0 },
});
defineEmits(['select', 'hover']);

const keyFor = c => {
  if (c.is_all) return 'all';
  if (c.is_ai) return `ai-${c.id}`;
  return `u-${c.id}`;
};
</script>

<template>
  <div
    class="absolute bottom-full left-12 mb-2 w-64 z-30 rounded-lg shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden"
  >
    <p class="px-3 py-1.5 text-[10px] font-medium uppercase tracking-wide text-n-slate-11 border-b border-n-weak">
      Mencionar
    </p>
    <ul class="max-h-[260px] overflow-y-auto ic-thread-scroll">
      <li v-if="candidates.length === 0" class="px-3 py-3 text-xs text-center text-n-slate-11">
        Nenhum membro encontrado
      </li>
      <li
        v-for="(c, idx) in candidates"
        :key="keyFor(c)"
      >
        <button
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-start transition"
          :class="idx === highlightedIndex ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
          @mousedown.prevent="$emit('select', c)"
          @mouseenter="$emit('hover', idx)"
        >
          <!-- Todos -->
          <template v-if="c.is_all">
            <span class="size-6 inline-flex items-center justify-center rounded-full bg-n-brand text-white shrink-0">
              <span class="i-lucide-at-sign text-sm" />
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-n-slate-12">{{ c.name }}</p>
              <p class="text-[10px] text-n-slate-11 truncate">{{ c.description }}</p>
            </div>
          </template>
          <!-- Bea / humano -->
          <template v-else>
            <Avatar
              :name="c.name"
              :src="c.avatar_url || ''"
              :size="24"
              :icon-name="c.is_ai ? 'i-lucide-sparkles' : null"
              rounded-full
            />
            <span class="flex-1 text-sm truncate text-n-slate-12">{{ c.name }}</span>
            <span
              v-if="c.is_ai"
              class="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded bg-n-brand text-white"
            >
              IA
            </span>
          </template>
        </button>
      </li>
    </ul>
  </div>
</template>
