<script setup>
// FE-2 (auditoria 2026-05-18): extraído de GroupSettingsDrawer.vue (601 LOC).
// Header do drawer com botão X (view principal) ou voltar (sub-views
// arquivos/favoritos) + título dinâmico. Estilo WhatsApp.
//
// FE-6: `<Tooltip>` substituiu `title=` nativo no lote anterior — preservar.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

defineProps({
  // 'main' | 'files' | 'favorites'
  view: { type: String, required: true },
  title: { type: String, required: true },
});

defineEmits(['close', 'back']);
</script>

<template>
  <!-- h-[60px] alinhado com sidebar "Chat interno", header da room
       ("Recepção"), header da Menções e DmUserDrawer. Padrão V2. -->
  <header class="flex items-center gap-3 px-4 h-[60px] border-b border-n-weak shrink-0">
    <Tooltip v-if="view === 'main'" :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HEADER.CLOSE_TOOLTIP')">
      <button
        type="button"
        class="inline-flex items-center justify-center p-0 rounded-md text-n-slate-11 hover:text-n-slate-12"
        @click="$emit('close')"
      >
        <span class="i-lucide-x text-xl" />
      </button>
    </Tooltip>
    <Tooltip v-else :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HEADER.BACK_TOOLTIP')">
      <button
        type="button"
        class="inline-flex items-center justify-center p-0 rounded-md text-n-slate-11 hover:text-n-slate-12"
        @click="$emit('back')"
      >
        <span class="i-lucide-arrow-left text-xl" />
      </button>
    </Tooltip>
    <h3 class="text-base font-semibold text-n-slate-12">
      {{ title }}
    </h3>
  </header>
</template>
