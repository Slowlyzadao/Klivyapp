<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  roomId: { type: Number, required: true },
});

const store = useStore();

const typers = computed(() =>
  store.getters['internalChatTyping/getTypersForRoom'](props.roomId)
);

const text = computed(() => {
  const list = typers.value;
  if (list.length === 0) return '';
  if (list.length === 1) return `${list[0].name} está digitando…`;
  if (list.length === 2) return `${list[0].name} e ${list[1].name} estão digitando…`;
  return `${list[0].name} e mais ${list.length - 1} estão digitando…`;
});
</script>

<template>
  <div
    v-if="text"
    class="flex items-center gap-1.5 px-4 py-1.5 text-xs text-n-slate-11 bg-n-background"
  >
    <span class="flex items-center gap-0.5">
      <span class="w-1 h-1 rounded-full bg-n-slate-10 ic-typing-dot" style="animation-delay:0s" />
      <span class="w-1 h-1 rounded-full bg-n-slate-10 ic-typing-dot" style="animation-delay:.15s" />
      <span class="w-1 h-1 rounded-full bg-n-slate-10 ic-typing-dot" style="animation-delay:.3s" />
    </span>
    <span class="italic">{{ text }}</span>
  </div>
</template>
