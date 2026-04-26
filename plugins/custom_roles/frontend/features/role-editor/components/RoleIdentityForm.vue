<script setup>
import Input from 'dashboard/components-next/input/Input.vue';

defineProps({
  name: { type: String, required: true },
  description: { type: String, default: '' },
});

defineEmits(['update:name', 'update:description']);
</script>

<template>
  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
    <div class="flex flex-col gap-1.5 md:col-span-1">
      <label
        class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider"
      >
        Nome da função *
      </label>
      <Input
        :model-value="name"
        placeholder="Ex: Atendimento Comercial"
        :maxlength="80"
        size="sm"
        @update:model-value="$emit('update:name', $event)"
      />
    </div>
    <div class="flex flex-col gap-1.5 md:col-span-2">
      <label
        class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider"
      >
        Descrição
      </label>
      <Input
        :model-value="description"
        placeholder="Ex: Acesso à agenda e contatos, sem prontuário."
        :maxlength="240"
        size="sm"
        @update:model-value="$emit('update:description', $event)"
      />
    </div>
  </div>
</template>
