<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  isEditing: { type: Boolean, default: false },
  totalActive: { type: Number, default: 0 },
  isSaving: { type: Boolean, default: false },
  canSave: { type: Boolean, default: false },
});

defineEmits(['back', 'save']);
</script>

<template>
  <div class="flex items-center justify-between gap-4 mb-2">
    <div class="flex items-center gap-3 min-w-0">
      <button
        class="inline-flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3 px-2 py-1 rounded-md transition-colors"
        @click="$emit('back')"
      >
        <i class="i-lucide-chevron-left w-4 h-4" />
        <span>Funções</span>
      </button>
      <h1 class="text-heading-1 text-n-slate-12 truncate">
        {{ isEditing ? 'Editar função' : 'Nova função' }}
      </h1>
      <span
        class="px-2 py-0.5 rounded-md bg-n-slate-3 text-[11px] font-medium text-n-slate-11 whitespace-nowrap"
      >
        {{ totalActive }} permissões ativas
      </span>
    </div>
    <Button
      label="Salvar função"
      icon="i-lucide-save"
      size="sm"
      :is-loading="isSaving"
      :disabled="!canSave"
      @click="$emit('save')"
    />
  </div>
</template>
