<script setup>
defineProps({
  mode: { type: String, required: true },
});

defineEmits(['update:mode']);
</script>

<template>
  <div class="flex gap-2 p-1 bg-n-slate-3 rounded-lg w-fit">
    <button
      class="px-4 py-1.5 rounded-md text-sm font-medium transition-all"
      :class="[
        mode === 'preset'
          ? 'bg-n-slate-1 text-n-slate-12 shadow-sm'
          : 'text-n-slate-11 hover:text-n-slate-12',
      ]"
      @click="$emit('update:mode', 'preset')"
    >
      Perfis Prontos
    </button>
    <button
      class="px-4 py-1.5 rounded-md text-sm font-medium transition-all"
      :class="[
        mode === 'custom'
          ? 'bg-n-slate-1 text-n-slate-12 shadow-sm'
          : 'text-n-slate-11 hover:text-n-slate-12',
      ]"
      @click="$emit('update:mode', 'custom')"
    >
      Personalizado
    </button>
  </div>
</template>
