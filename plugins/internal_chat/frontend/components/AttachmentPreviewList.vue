<script setup>
import { computed } from 'vue';

const props = defineProps({
  files: { type: Array, required: true },
});
defineEmits(['remove']);

const items = computed(() =>
  props.files.map((f, idx) => ({
    idx,
    name: f.name,
    size: f.size,
    type: f.type,
    isImage: (f.type || '').startsWith('image/'),
    url: (f.type || '').startsWith('image/') ? URL.createObjectURL(f) : null,
  }))
);

const formatSize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};
</script>

<template>
  <div
    v-if="items.length"
    class="flex flex-wrap gap-2 px-1 py-2 border-t border-n-weak"
  >
    <div
      v-for="item in items"
      :key="item.idx"
      class="relative flex items-center gap-2 px-2 py-1.5 rounded-md bg-n-alpha-1 border border-n-weak max-w-[220px]"
    >
      <img
        v-if="item.isImage"
        :src="item.url"
        :alt="item.name"
        class="object-cover w-10 h-10 rounded"
      >
      <span
        v-else
        class="i-lucide-file text-2xl text-n-slate-11 shrink-0"
      />
      <div class="flex-1 min-w-0">
        <p class="text-xs font-medium truncate text-n-slate-12">{{ item.name }}</p>
        <p class="text-[10px] text-n-slate-11">{{ formatSize(item.size) }}</p>
      </div>
      <button
        type="button"
        class="absolute -top-1.5 -right-1.5 inline-flex items-center justify-center w-5 h-5 rounded-full bg-n-solid-3 text-n-slate-12 hover:bg-n-ruby-9 hover:text-white"
        @click="$emit('remove', item.idx)"
      >
        <span class="i-lucide-x text-xs" />
      </button>
    </div>
  </div>
</template>
