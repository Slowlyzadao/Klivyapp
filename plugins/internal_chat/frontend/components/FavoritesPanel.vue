<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// FE-8: BeclinicButton para botão de retry. Demais (unfavorite em Tooltip)
// ficam nativos por terem comportamento contextual com Tooltip wrapper.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  roomId: { type: Number, required: true },
});
defineEmits(['jump-to-message']);

const store = useStore();
const favorites = ref([]);
const meta = ref(null); // FE-21: page/per_page/total do backend
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
    const res = await store.dispatch('internalChatMessages/fetchFavorites', {
      roomId: props.roomId,
    });
    // FE-21: store agora retorna `{ items, meta }`. Compat com forma antiga
    // (array direto) preservada.
    if (Array.isArray(res)) {
      favorites.value = res;
      meta.value = null;
    } else {
      favorites.value = res.items || [];
      meta.value = res.meta || null;
    }
  } catch {
    error.value = 'Falha ao carregar favoritos';
  } finally {
    loading.value = false;
  }
};

// FE-21: avisa quando há favoritos antigos invisíveis (total > per_page).
const hasMoreInvisible = computed(
  () => meta.value && meta.value.total > meta.value.per_page
);

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
        {{ $t('INTERNAL_CHAT.FAVORITES.DESCRIPTION') }}
      </p>
      <!-- FE-21: aviso quando há mais favoritos antigos invisíveis. -->
      <p
        v-if="hasMoreInvisible"
        class="text-[11px] text-n-amber-11 mt-1.5 flex items-center gap-1"
      >
        <span class="i-lucide-info text-sm" />
        {{ $t('INTERNAL_CHAT.FAVORITES.LIMIT_WARNING', { perPage: meta.per_page, total: meta.total }) }}
      </p>
    </div>

    <div v-if="loading" class="flex items-center justify-center py-8 text-sm text-n-slate-11">
      <span class="i-lucide-loader-2 animate-spin mr-2 text-base" />
      {{ $t('INTERNAL_CHAT.SIDEBAR.LOADING') }}
    </div>

    <div v-else-if="error" class="flex flex-col items-center py-8 text-sm text-n-ruby-11">
      <span class="i-lucide-alert-circle text-2xl mb-1" />
      {{ error }}
      <BeclinicButton
        class="mt-2"
        label="Tentar de novo"
        variant="link"
        size="sm"
        @click="fetchFavorites"
      />
    </div>

    <div v-else-if="isEmpty" class="flex flex-col items-center py-12 text-sm text-n-slate-11">
      <span class="i-lucide-star text-3xl mb-2 text-n-slate-9" />
      <p>{{ $t('INTERNAL_CHAT.FAVORITES.EMPTY') }}</p>
      <p class="text-xs mt-1 text-n-slate-10">
        {{ $t('INTERNAL_CHAT.FAVORITES.EMPTY_HINT') }}
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
        <Tooltip :label="$t('INTERNAL_CHAT.FAVORITES.REMOVE_TOOLTIP')">
          <button
            type="button"
            class="shrink-0 p-1.5 rounded-md text-n-amber-11 hover:bg-n-amber-3"
            @click.stop="onUnfavorite(msg)"
          >
            <span class="i-lucide-star-off text-sm" />
          </button>
        </Tooltip>
      </li>
    </ul>
  </div>
</template>
