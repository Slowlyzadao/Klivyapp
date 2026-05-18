<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  roomId: { type: Number, required: true },
});
defineEmits(['jump-to-message']);

const store = useStore();
const favorites = ref([]);
const loading = ref(false);
const error = ref('');

const PREVIEW_LABELS = {
  image: '📷 Imagem',
  audio: '🎵 Áudio',
  video: '🎬 Vídeo',
  file: '📎 Arquivo',
  sticker: '🎨 Figurinha',
};

const fetchFavorites = async () => {
  loading.value = true;
  error.value = '';
  try {
    const list = await store.dispatch('internalChatMessages/fetchFavorites', {
      roomId: props.roomId,
    });
    favorites.value = list;
  } catch {
    error.value = 'Falha ao carregar favoritos';
  } finally {
    loading.value = false;
  }
};

onMounted(fetchFavorites);

const formatTime = ts => {
  if (!ts) return '';
  const d = new Date(ts);
  const today = new Date();
  if (d.toDateString() === today.toDateString()) {
    return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  }
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' });
};

const previewFor = msg => {
  if (msg.deleted_at) return 'Mensagem apagada';
  if (msg.content_type === 'sticker') return PREVIEW_LABELS.sticker;
  if (msg.content_type !== 'text' && msg.attachments?.length) {
    const att = msg.attachments[0];
    return PREVIEW_LABELS[att.file_type] || '📎 Anexo';
  }
  return msg.content || (msg.attachments?.[0] ? PREVIEW_LABELS[msg.attachments[0].file_type] : '');
};

const senderName = msg => msg.sender?.name || 'Sistema';

const onUnfavorite = async msg => {
  try {
    await store.dispatch('internalChatMessages/toggleFavorite', {
      roomId: msg.room_id,
      messageId: msg.id,
    });
    favorites.value = favorites.value.filter(m => m.id !== msg.id);
  } catch {
    // silencioso
  }
};

const isEmpty = computed(() => !loading.value && favorites.value.length === 0);
</script>

<template>
  <div class="flex flex-col flex-1 overflow-hidden">
    <div class="px-5 py-3 border-b border-n-weak">
      <p class="text-xs text-n-slate-11">
        Mensagens que você marcou como favoritas. Esta lista é individual.
      </p>
    </div>

    <div v-if="loading" class="flex items-center justify-center py-8 text-sm text-n-slate-11">
      <span class="i-lucide-loader-2 animate-spin mr-2 text-base" />
      Carregando…
    </div>

    <div v-else-if="error" class="flex flex-col items-center py-8 text-sm text-n-ruby-11">
      <span class="i-lucide-alert-circle text-2xl mb-1" />
      {{ error }}
      <button
        type="button"
        class="mt-2 text-xs text-n-brand hover:underline"
        @click="fetchFavorites"
      >
        Tentar de novo
      </button>
    </div>

    <div v-else-if="isEmpty" class="flex flex-col items-center py-12 text-sm text-n-slate-11">
      <span class="i-lucide-star text-3xl mb-2 text-n-slate-9" />
      <p>Você ainda não favoritou nenhuma mensagem aqui.</p>
      <p class="text-xs mt-1 text-n-slate-10">
        Clique no chevron de uma mensagem e escolha "Favoritar".
      </p>
    </div>

    <ul v-else class="flex-1 overflow-y-auto divide-y divide-n-weak">
      <li
        v-for="msg in favorites"
        :key="msg.id"
        class="flex items-start gap-3 px-5 py-3 hover:bg-n-alpha-1 cursor-pointer transition"
        @click="$emit('jump-to-message', msg.id)"
      >
        <Avatar
          :name="senderName(msg)"
          :src="msg.sender?.avatar_url || ''"
          :size="32"
          rounded-full
        />
        <div class="flex-1 min-w-0">
          <div class="flex items-center justify-between gap-2">
            <p class="text-sm font-medium truncate text-n-slate-12">
              {{ senderName(msg) }}
            </p>
            <span class="text-[10px] text-n-slate-10 shrink-0">
              {{ formatTime(msg.created_at) }}
            </span>
          </div>
          <p class="text-xs text-n-slate-11 line-clamp-2 mt-0.5">
            {{ previewFor(msg) }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 p-1.5 rounded-md text-n-amber-11 hover:bg-n-amber-3"
          title="Remover dos favoritos"
          @click.stop="onUnfavorite(msg)"
        >
          <span class="i-lucide-star-off text-sm" />
        </button>
      </li>
    </ul>
  </div>
</template>
