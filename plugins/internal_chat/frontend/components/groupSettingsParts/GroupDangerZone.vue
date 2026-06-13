<script setup>
// FE-2 (auditoria 2026-05-18): extraído de GroupSettingsDrawer.vue (601 LOC).
// Danger zone do drawer: botões "Sair do grupo" / "Excluir grupo".
// `confirm()` nativo + dispatches ficam no pai — aqui só emitimos request.
defineProps({
  currentMembership: { type: Object, default: null },
  isOwner: { type: Boolean, default: false },
  isDeletingGroup: { type: Boolean, default: false },
});

defineEmits(['leave', 'delete-group']);
</script>

<template>
  <section class="py-2 mt-auto">
    <button
      v-if="currentMembership"
      type="button"
      class="flex items-center w-full gap-3 px-5 py-3 text-start text-n-ruby-11 hover:bg-n-ruby-3 transition"
      @click="$emit('leave')"
    >
      <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-ruby-3 text-n-ruby-11">
        <span class="i-lucide-log-out text-base" />
      </span>
      <span class="text-sm font-medium">{{ $t('INTERNAL_CHAT.GROUP_SETTINGS.DANGER_ZONE.LEAVE') }}</span>
    </button>
    <button
      v-if="isOwner"
      type="button"
      class="flex items-center w-full gap-3 px-5 py-3 text-start text-n-ruby-11 hover:bg-n-ruby-3 transition disabled:opacity-50"
      :disabled="isDeletingGroup"
      @click="$emit('delete-group')"
    >
      <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-ruby-3 text-n-ruby-11">
        <span class="i-lucide-trash-2 text-base" />
      </span>
      <span class="text-sm font-medium">
        {{ isDeletingGroup ? $t('INTERNAL_CHAT.GROUP_SETTINGS.DANGER_ZONE.DELETING') : $t('INTERNAL_CHAT.GROUP_SETTINGS.DANGER_ZONE.DELETE') }}
      </span>
    </button>
  </section>
</template>
