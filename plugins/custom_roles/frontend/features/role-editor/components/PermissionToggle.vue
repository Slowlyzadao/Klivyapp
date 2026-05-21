<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  label: { type: String, required: true },
  modelValue: { type: Boolean, default: false },
});

defineEmits(['update:modelValue']);
</script>

<template>
  <div
    class="flex items-center justify-between px-4 py-2.5 hover:bg-n-slate-2 transition-colors"
  >
    <span class="text-sm text-n-slate-11">{{ label }}</span>
    <Switch
      :model-value="modelValue"
      @update:model-value="$emit('update:modelValue', $event)"
    />
  </div>
</template>
