<script setup>
// FE-1 (auditoria 2026-05-19): extraído de MessageBubble.vue — aparecia
// duplicado nos blocos sticker e bolha normal. Display-only: sem state
// local, sem store. A classe `ic-tick-read` (cor azul quando lido) é
// definida no `<style>` global do MessageBubble.vue pai e fica acessível
// porque NÃO é scoped — preferimos compartilhar a regra a duplicar.
//
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): tooltip "Lida"/"Enviada"
// migrado pra `INTERNAL_CHAT.MESSAGE.TICK_READ`/`TICK_SENT` (chaves já
// existentes no namespace MESSAGE — não duplicamos).
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

defineProps({
  isRead: { type: Boolean, default: false },
});
</script>

<template>
  <Tooltip
    :label="isRead ? $t('INTERNAL_CHAT.MESSAGE.TICK_READ') : $t('INTERNAL_CHAT.MESSAGE.TICK_SENT')"
    :class="isRead ? 'ic-tick-read' : ''"
  >
    <span v-if="isRead" class="i-lucide-check-check text-sm" />
    <span v-else class="i-lucide-check text-sm" />
  </Tooltip>
</template>
