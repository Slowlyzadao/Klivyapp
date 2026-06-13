<script setup>
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.ROOM_LIST_ITEM.*` via i18n. `useI18n()` é usado em JS pra
// resolver `PREVIEW_LABELS` (computed dinâmico baseado em content_type) e
// fallbacks de nome de sala/mensagem apagada. Datas formatadas via API
// nativa (`toLocaleTimeString`/`toLocaleDateString`) — locale data não
// migrado por ser localizado pelo runtime.
import { computed, nextTick, onBeforeUnmount, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import PresenceDot from './PresenceDot.vue';

const props = defineProps({
  room: { type: Object, required: true },
});

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const showMenu = ref(false);
// Ref no botão "..." — usado pra calcular position fixed do menu via
// getBoundingClientRect. Sem isso o menu absoluto era clipado pelo
// container do RecycleScroller (overflow: hidden).
const moreBtnRef = ref(null);
const menuStyle = ref({ top: '0px', left: '0px' });

const isActive = computed(
  () => Number(route.params.roomId) === Number(props.room.id)
);

const unread = computed(
  () => store.getters['internalChatRooms/getUnreadByRoom'](props.room.id)
);
// Indicador @ no badge (estilo WhatsApp) — só aparece se eu fui mencionado
// e ainda não li. Independente do contador de mensagens normal.
const unreadMentions = computed(
  () => store.getters['internalChatMentions/getUnreadCountByRoom'](props.room.id)
);

const isMuted = computed(() => {
  if (!props.room.muted_until) return false;
  return new Date(props.room.muted_until).getTime() > Date.now();
});

const isArchived = computed(() => !!props.room.archived_at);

// PREVIEW_LABELS é computed pra resolver via `t()` — labels mudam de locale
// junto da UI. Chaves bate com `content_type` do backend (`image`/`audio`/
// `video`/`file`).
const previewLabels = computed(() => ({
  image: t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_IMAGE'),
  audio: t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_AUDIO'),
  video: t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_VIDEO'),
  file: t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_FILE'),
}));
const lastPreview = computed(() => {
  const msg = props.room.last_message;
  if (!msg) return t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_EMPTY');
  if (msg.deleted_at) return t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_DELETED');
  if (msg.content_type === 'system') return msg.content || '';
  if (msg.content_type !== 'text') {
    return previewLabels.value[msg.content_type] || `[${msg.content_type}]`;
  }
  if (msg.content) return msg.content;
  if (msg.attachments?.length) {
    const first = msg.attachments[0];
    return (
      previewLabels.value[first.file_type] ||
      t('INTERNAL_CHAT.ROOM_LIST_ITEM.PREVIEW_ATTACHMENT')
    );
  }
  return '';
});

const otherUserId = computed(() => {
  if (props.room.kind !== 'direct') return null;
  const me = store.getters.getCurrentUserID;
  return props.room.members?.find(m => m.user_id !== me)?.user_id || null;
});

const formattedTime = computed(() => {
  const ts = props.room.last_message_at || props.room.created_at;
  if (!ts) return '';
  const d = new Date(ts);
  const today = new Date();
  if (d.toDateString() === today.toDateString()) {
    return d.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    });
  }
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
});

const open = () => {
  router.push({
    name: 'internal_chat_room',
    params: { accountId: route.params.accountId, roomId: props.room.id },
  });
};

// Posição do menu: abaixo-direita do botão, com clamp de viewport.
// Altura estimada: 2 ações × ~36px + padding ≈ 76px.
const MENU_WIDTH = 176; // w-44
const MENU_HEIGHT = 88;
const computeMenuPosition = () => {
  const btn = moreBtnRef.value;
  if (!btn || typeof btn.getBoundingClientRect !== 'function') return;
  const rect = btn.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  let top = rect.bottom + 4;
  let left = rect.right - MENU_WIDTH;
  if (left < 8) left = 8;
  if (left + MENU_WIDTH > vw - 8) left = vw - MENU_WIDTH - 8;
  // Sem espaço embaixo (item perto do composer): flipa pra cima do botão.
  if (top + MENU_HEIGHT > vh - 8) {
    top = Math.max(8, rect.top - MENU_HEIGHT - 4);
  }
  menuStyle.value = { top: `${top}px`, left: `${left}px` };
};

const toggleMenu = async e => {
  e.stopPropagation();
  if (showMenu.value) {
    showMenu.value = false;
    return;
  }
  showMenu.value = true;
  await nextTick();
  computeMenuPosition();
  // Re-posiciona em scroll/resize enquanto o menu estiver aberto.
  window.addEventListener('scroll', computeMenuPosition, true);
  window.addEventListener('resize', computeMenuPosition);
};
const closeMenu = () => {
  showMenu.value = false;
  window.removeEventListener('scroll', computeMenuPosition, true);
  window.removeEventListener('resize', computeMenuPosition);
};
onBeforeUnmount(() => {
  window.removeEventListener('scroll', computeMenuPosition, true);
  window.removeEventListener('resize', computeMenuPosition);
});

const toggleMute = async () => {
  try {
    if (isMuted.value) {
      await store.dispatch('internalChatRooms/unmute', props.room.id);
    } else {
      // Mesma duração do drawer (8h) — antes a lista mutava ~permanente.
      const until = new Date(Date.now() + 8 * 3600 * 1000).toISOString();
      await store.dispatch('internalChatRooms/mute', { roomId: props.room.id, until });
    }
  } catch (e) {
    useAlert(t('INTERNAL_CHAT.ROOM_LIST_ITEM.ACTION_ERROR'));
  } finally {
    closeMenu();
  }
};
const toggleArchive = async () => {
  try {
    if (isArchived.value) {
      await store.dispatch('internalChatRooms/unarchive', props.room.id);
    } else {
      await store.dispatch('internalChatRooms/archive', props.room.id);
    }
  } catch (e) {
    useAlert(t('INTERNAL_CHAT.ROOM_LIST_ITEM.ACTION_ERROR'));
  } finally {
    closeMenu();
  }
};
</script>

<template>
  <li class="relative group/item px-2">
    <button
      type="button"
      class="flex items-start w-full gap-3 px-3 py-2.5 transition rounded-lg text-start hover:bg-n-alpha-1"
      :class="isActive ? 'bg-n-alpha-2' : ''"
      @click="open"
    >
      <div class="relative shrink-0">
        <Avatar
          :key="room.avatar_updated_at || 'no-avatar'"
          :name="room.name || $t('INTERNAL_CHAT.ROOM_LIST_ITEM.ROOM_FALLBACK_NAME')"
          :src="room.avatar_url || ''"
          :size="40"
          rounded-full
        />
        <PresenceDot
          v-if="otherUserId"
          :user-id="otherUserId"
          :size="11"
          class="absolute bottom-0 right-0"
        />
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center justify-between gap-2 leading-tight">
          <p class="text-sm font-medium truncate text-n-slate-12 flex items-center gap-1">
            <span class="truncate">
              {{ room.name || $t('INTERNAL_CHAT.ROOM_LIST_ITEM.ROOM_FALLBACK_NAME') }}
            </span>
            <span v-if="isMuted" class="i-lucide-bell-off text-xs text-n-slate-10" />
          </p>
          <span class="text-[11px] text-n-slate-10 shrink-0">
            {{ formattedTime }}
          </span>
        </div>
        <div class="flex items-center justify-between gap-2 mt-1 leading-tight">
          <p class="text-xs truncate text-n-slate-11 leading-tight">{{ lastPreview }}</p>
          <div class="flex items-center gap-1 shrink-0">
            <!-- FE-6: Tooltip envolve badge "@" — span interno mantém visual
                 da pílula; Tooltip-host é inline-flex e não quebra o flow. -->
            <Tooltip
              v-if="unreadMentions > 0"
              :label="$t('INTERNAL_CHAT.ROOM_LIST_ITEM.MENTIONED_TOOLTIP')"
            >
              <span
                class="inline-flex items-center justify-center w-[18px] h-[18px] text-[11px] font-semibold rounded-full text-white"
                :class="isMuted ? 'bg-n-slate-9' : 'bg-n-brand'"
              >
                @
              </span>
            </Tooltip>
            <span
              v-if="unread > 0"
              class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 text-[10px] font-semibold rounded-full text-white"
              :class="isMuted ? 'bg-n-slate-9' : 'bg-n-brand'"
            >
              {{ unread > 99 ? '99+' : unread }}
            </span>
          </div>
        </div>
      </div>
    </button>

    <!-- Botão "Mais ações": shadow-md + bg-solid-1 sólido + text-slate-12
         garantem contraste mesmo quando o card está em hover/active
         (antes `bg-n-alpha-1` no hover blendava com o card). -->
    <Tooltip
      :label="$t('INTERNAL_CHAT.ROOM_LIST_ITEM.MORE_ACTIONS_TOOLTIP')"
      class="absolute top-2 right-2 opacity-0 group-hover/item:opacity-100 focus-within:opacity-100 transition"
    >
      <button
        ref="moreBtnRef"
        type="button"
        class="w-7 h-7 rounded-md flex items-center justify-center bg-n-solid-1 border border-n-weak shadow-sm text-n-slate-12 hover:bg-n-slate-3"
        @click="toggleMenu"
      >
        <span class="i-lucide-more-horizontal text-base" />
      </button>
    </Tooltip>

    <!-- Menu via Teleport+fixed: escapa do overflow do RecycleScroller.
         Backdrop fixed inset-0 captura click-outside pra fechar. -->
    <Teleport to="body">
      <template v-if="showMenu">
        <div
          class="ic-app fixed z-50 w-44 rounded-lg shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden"
          :style="menuStyle"
          @click.stop
          @mousedown.stop
        >
          <button
            type="button"
            class="flex items-center w-full gap-2 px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="toggleMute"
          >
            <span :class="isMuted ? 'i-lucide-bell' : 'i-lucide-bell-off'" class="text-base" />
            {{
              isMuted
                ? $t('INTERNAL_CHAT.ROOM_LIST_ITEM.ACTION_UNMUTE')
                : $t('INTERNAL_CHAT.ROOM_LIST_ITEM.ACTION_MUTE')
            }}
          </button>
          <button
            type="button"
            class="flex items-center w-full gap-2 px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="toggleArchive"
          >
            <span :class="isArchived ? 'i-lucide-archive-restore' : 'i-lucide-archive'" class="text-base" />
            {{ isArchived
                ? $t('INTERNAL_CHAT.ROOM_LIST_ITEM.ACTION_UNARCHIVE')
                : $t('INTERNAL_CHAT.ROOM_LIST_ITEM.ACTION_ARCHIVE') }}
          </button>
        </div>
        <div class="fixed inset-0 z-40" @click="closeMenu" />
      </template>
    </Teleport>
  </li>
</template>
