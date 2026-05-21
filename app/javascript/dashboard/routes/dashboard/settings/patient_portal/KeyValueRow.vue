<script setup>
// Linha label/valor read-only para mostrar setting individual.
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number, Boolean, Array], default: '' },
});
</script>

<template>
  <div class="flex items-baseline justify-between gap-4 py-2 border-b border-n-weak last:border-0">
    <span class="text-sm text-n-slate-11">{{ label }}</span>
    <span class="text-sm font-medium text-n-slate-12 text-right">
      <template v-if="Array.isArray(value)">
        {{ value.length ? value.join(', ') : '—' }}
      </template>
      <template v-else-if="typeof value === 'boolean'">
        {{ value ? 'Sim' : 'Não' }}
      </template>
      <template v-else-if="value === null || value === undefined || value === ''">—</template>
      <template v-else>{{ value }}</template>
    </span>
  </div>
</template>
