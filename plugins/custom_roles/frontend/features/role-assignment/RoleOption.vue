<script setup>
defineProps({
  role: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  totalPermissions: { type: Number, default: 0 },
});

defineEmits(['select']);
</script>

<template>
  <button
    type="button"
    class="flex items-center gap-3 w-full px-4 py-3 rounded-xl border text-left transition-colors"
    :class="
      selected
        ? 'border-n-brand bg-n-brand/5'
        : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'
    "
    @click="$emit('select')"
  >
    <span
      class="flex items-center justify-center w-5 h-5 rounded-full border-2 flex-shrink-0 transition-colors"
      :class="selected ? 'border-n-brand' : 'border-n-slate-6'"
    >
      <span
        v-if="selected"
        class="block w-2.5 h-2.5 rounded-full bg-n-brand"
      />
    </span>

    <span class="flex-1 flex flex-col gap-0.5 min-w-0">
      <span class="text-sm font-semibold text-n-slate-12 truncate">
        {{ role.name }}
      </span>
      <span
        v-if="role.description"
        class="text-xs text-n-slate-11 truncate"
      >
        {{ role.description }}
      </span>
    </span>

    <span
      class="px-2 py-0.5 rounded-md bg-n-slate-3 text-[11px] font-medium text-n-slate-11 whitespace-nowrap"
    >
      {{ totalPermissions }} permissões
    </span>
  </button>
</template>
