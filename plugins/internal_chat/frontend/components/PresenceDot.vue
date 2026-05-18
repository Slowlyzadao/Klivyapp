<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  userId: { type: [Number, String], default: null },
  size: { type: Number, default: 10 },
  withRing: { type: Boolean, default: true },
});

const store = useStore();

const status = computed(() => {
  if (!props.userId) return 'offline';
  const agent = store.getters['agents/getAgentById'](props.userId);
  return agent?.availability_status || 'offline';
});

const colorClass = computed(() => {
  switch (status.value) {
    case 'online':
      return 'bg-n-teal-10';
    case 'busy':
      return 'bg-n-amber-10';
    default:
      return 'bg-n-slate-7';
  }
});

const sizeStyle = computed(() => ({
  width: `${props.size}px`,
  height: `${props.size}px`,
}));
</script>

<template>
  <span
    class="inline-block rounded-full"
    :class="[colorClass, withRing ? 'ring-2 ring-n-solid-1' : '']"
    :style="sizeStyle"
    :title="status"
  />
</template>
