<script setup>
import { computed } from 'vue';

const props = defineProps({
  message: { type: Object, required: true },
  compact: { type: Boolean, default: false }, // true = embed em bubble; false = preview no composer
  isOwn: { type: Boolean, default: false },
});
defineEmits(['close', 'click']);

const PREVIEW_LABELS = {
  image: '📷 Imagem',
  audio: '🎵 Áudio',
  video: '🎬 Vídeo',
  file: '📎 Arquivo',
};

const previewText = computed(() => {
  if (props.message.deleted_at) return 'Mensagem apagada';
  if (props.message.content_type === 'system') return 'Mensagem do sistema';
  if (props.message.content_type === 'sticker') return '🎨 Figurinha';
  if (props.message.content_preview) return props.message.content_preview;
  if (props.message.content) return props.message.content;
  if (props.message.first_attachment_type) {
    return PREVIEW_LABELS[props.message.first_attachment_type] || '📎 Anexo';
  }
  if (props.message.attachments?.length) {
    return PREVIEW_LABELS[props.message.attachments[0].file_type] || '📎 Anexo';
  }
  return '';
});

const senderName = computed(
  () => props.message.sender_name || props.message.sender?.name || 'Usuário'
);

// Miniatura à direita do quote (sticker ou imagem). Pra texto puro, é null.
const thumbUrl = computed(() => {
  if (props.message.thumb_url) return props.message.thumb_url;
  // fallback caso o backend não tenha enviado mas o objeto local tem
  if (props.message.sticker?.image_url) return props.message.sticker.image_url;
  const att = props.message.attachments?.[0];
  if (att?.file_type === 'image') return att.thumb_url || att.file_url;
  return null;
});
</script>

<template>
  <!-- Embed dentro do bubble (compact=true). Linha única com nome + preview;
       miniatura à direita pra sticker/imagem (estilo WhatsApp). -->
  <button
    v-if="compact"
    type="button"
    class="ic-reply-embed block w-full text-left mb-1 pl-2 pr-2 py-1 rounded border-l-2 cursor-pointer transition overflow-hidden"
    :class="isOwn ? 'ic-reply-embed-own' : 'bg-n-alpha-1 border-n-brand hover:bg-n-alpha-2'"
    @click="$emit('click')"
  >
    <div class="flex items-center gap-2">
      <div class="flex-1 min-w-0">
        <p
          class="text-[11px] font-semibold truncate"
          :class="isOwn ? 'ic-reply-name-own' : 'text-n-brand'"
        >
          {{ senderName }}
        </p>
        <p
          class="text-xs truncate"
          :class="isOwn ? 'ic-reply-text-own' : 'text-n-slate-11'"
        >
          {{ previewText }}
        </p>
      </div>
      <img
        v-if="thumbUrl"
        :src="thumbUrl"
        class="shrink-0 w-10 h-10 rounded object-cover bg-n-alpha-2"
        alt=""
      >
    </div>
  </button>

  <!-- Preview no composer (compact=false) -->
  <div
    v-else
    class="flex items-start gap-2 px-3 py-2 mb-2 border-l-2 rounded bg-n-alpha-1 border-n-brand"
  >
    <span class="i-lucide-corner-up-left mt-0.5 text-base text-n-brand shrink-0" />
    <div class="flex-1 min-w-0">
      <p class="text-[11px] font-semibold text-n-brand truncate">
        Respondendo a {{ senderName }}
      </p>
      <p class="text-xs truncate text-n-slate-11">{{ previewText }}</p>
    </div>
    <img
      v-if="thumbUrl"
      :src="thumbUrl"
      class="shrink-0 w-10 h-10 rounded object-cover bg-n-alpha-2"
      alt=""
    >
    <button
      type="button"
      class="text-n-slate-11 hover:text-n-slate-12 shrink-0"
      title="Cancelar resposta"
      @click="$emit('close')"
    >
      <span class="i-lucide-x text-base" />
    </button>
  </div>
</template>

<style>
/* Reply embedado em bolha enviada (verde claro WhatsApp). Fundo levemente
   mais escuro que a bolha, borda verde escura, nome em verde escuro pra
   ficar com cara de "highlight" do WhatsApp. */
.ic-reply-embed-own {
  background-color: rgba(15, 23, 42, 0.06);
  border-color: #1d8a52;
}
.ic-reply-embed-own:hover {
  background-color: rgba(15, 23, 42, 0.10);
}
.ic-reply-name-own {
  color: #1d8a52;
}
.ic-reply-text-own {
  color: rgba(15, 23, 42, 0.65);
}
.dark .ic-reply-embed-own {
  background-color: rgba(255, 255, 255, 0.08);
  border-color: #6ee7b7;
}
.dark .ic-reply-embed-own:hover {
  background-color: rgba(255, 255, 255, 0.14);
}
.dark .ic-reply-name-own {
  color: #6ee7b7;
}
.dark .ic-reply-text-own {
  color: rgba(255, 255, 255, 0.78);
}
</style>
