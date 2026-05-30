<script setup>
// Card de seleção de preset do PatientPortal (Sprint G).
// Componente "burro" — só dispara `select` quando o admin clica. A página pai
// decide o que fazer (mostrar confirmação, aplicar via API, etc.).
defineProps({
  presetKey: { type: String, required: true },
  title: { type: String, required: true },
  summary: { type: String, required: true },
  active: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);
</script>

<template>
  <button
    type="button"
    :disabled="disabled"
    class="text-left p-4 rounded-lg border-2 transition-colors w-full"
    :class="[
      active
        ? 'border-n-brand bg-n-solid-active'
        : 'border-n-weak bg-n-background hover:border-n-strong',
      disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer',
    ]"
    @click="!disabled && emit('select', presetKey)"
  >
    <div class="flex items-start justify-between gap-2">
      <h4 class="text-sm font-semibold text-n-slate-12 m-0">{{ title }}</h4>
      <span
        v-if="active"
        class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-brand text-white"
      >
        Ativo
      </span>
    </div>
    <p class="text-xs text-n-slate-11 m-0 mt-2 leading-relaxed">
      {{ summary }}
    </p>
  </button>
</template>
