<script setup>
/**
 * DmUserDrawer — drawer lateral estilo WhatsApp para conversas DM (1:1).
 * Espelha o pattern do `GroupSettingsDrawer` (header com voltar, sub-views
 * arquivos/favoritos), mas simplificado: sem membros, sem edição inline,
 * sem danger zone.
 *
 * Sub-views: 'main' (perfil + ações), 'files', 'favorites'.
 *
 * Backdrop NÃO fecha — só o botão X (memória `feedback_modal_no_backdrop_close`).
 */
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FilesPanel from './FilesPanel.vue';
import FavoritesPanel from './FavoritesPanel.vue';
import PresenceDot from './PresenceDot.vue';

const props = defineProps({
  room: { type: Object, required: true },
  otherUserId: { type: [Number, String], required: true },
  initialView: { type: String, default: 'main' },
});
const emit = defineEmits(['close', 'jump-to-message']);

const store = useStore();
const { t } = useI18n();

const view = ref(props.initialView);
const isMutating = ref(false);

const otherUser = computed(() =>
  store.getters['agents/getAgentById'](props.otherUserId)
);

const headerTitle = computed(() => {
  if (view.value === 'files') return t('INTERNAL_CHAT.DM_DRAWER.FILES_TITLE');
  if (view.value === 'favorites') return t('INTERNAL_CHAT.DM_DRAWER.FAVORITES_TITLE');
  return t('INTERNAL_CHAT.DM_DRAWER.MAIN_TITLE');
});

const presenceLabel = computed(() => {
  const status = otherUser.value?.availability_status;
  if (status === 'online') return t('INTERNAL_CHAT.ROOM.STATUS_ONLINE');
  if (status === 'busy') return t('INTERNAL_CHAT.ROOM.STATUS_BUSY');
  return t('INTERNAL_CHAT.ROOM.STATUS_OFFLINE');
});

const presenceColor = computed(() => {
  const status = otherUser.value?.availability_status;
  if (status === 'online') return 'text-green-600';
  if (status === 'busy') return 'text-amber-600';
  return 'text-n-slate-10';
});

const displayName = computed(
  () => otherUser.value?.name || otherUser.value?.display_name || props.room.name || ''
);

const emailValue = computed(() => otherUser.value?.email || '');

const roleLabel = computed(() => {
  if (!otherUser.value) return '';
  if (otherUser.value.klivy_role?.name) return otherUser.value.klivy_role.name;
  if (otherUser.value.role === 'administrator') return t('INTERNAL_CHAT.DM_DRAWER.ROLE_ADMIN');
  return t('INTERNAL_CHAT.DM_DRAWER.ROLE_AGENT');
});

const isMuted = computed(() => {
  const until = props.room?.muted_until;
  if (!until) return false;
  return new Date(until) > new Date();
});

const muteUntilLabel = computed(() => {
  if (!isMuted.value) return '';
  const d = new Date(props.room.muted_until);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
});

const isArchived = computed(() => !!props.room?.archived_at);

const toggleMute = async () => {
  if (isMutating.value) return;
  isMutating.value = true;
  try {
    if (isMuted.value) {
      await store.dispatch('internalChatRooms/unmute', props.room.id);
    } else {
      const until = new Date(Date.now() + 8 * 3600 * 1000).toISOString();
      await store.dispatch('internalChatRooms/mute', { roomId: props.room.id, until });
    }
  } catch (e) {
    useAlert(t('INTERNAL_CHAT.DM_DRAWER.ACTION_ERROR'));
  } finally {
    isMutating.value = false;
  }
};

const toggleArchive = async () => {
  if (isMutating.value) return;
  isMutating.value = true;
  try {
    if (isArchived.value) {
      await store.dispatch('internalChatRooms/unarchive', props.room.id);
    } else {
      await store.dispatch('internalChatRooms/archive', props.room.id);
      // Arquivou: a conversa saiu da lista — fecha o drawer (e a sala aberta
      // fica fora da lista até ser desarquivada na aba "Arquivadas").
      emit('close');
    }
  } catch (e) {
    useAlert(t('INTERNAL_CHAT.DM_DRAWER.ACTION_ERROR'));
  } finally {
    isMutating.value = false;
  }
};
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-end bg-black/40">
    <aside
      class="flex flex-col w-full h-full max-w-md overflow-hidden border-l shadow-2xl bg-n-solid-1 border-n-weak"
    >
      <!-- ── Header ─────────────────────────────────────────────────── -->
      <!-- h-[60px] alinhado com sidebar "Chat interno" + room header
           ("Leandro"). Layout V2 padronizado. -->
      <header class="flex items-center gap-3 px-4 h-[60px] border-b border-n-weak shrink-0">
        <Tooltip v-if="view === 'main'" :label="$t('INTERNAL_CHAT.DM_DRAWER.CLOSE_TOOLTIP')">
          <button
            type="button"
            class="inline-flex items-center justify-center p-0 rounded-md text-n-slate-11 hover:text-n-slate-12"
            @click="emit('close')"
          >
            <span class="i-lucide-x text-xl" />
          </button>
        </Tooltip>
        <Tooltip v-else :label="$t('INTERNAL_CHAT.DM_DRAWER.BACK_TOOLTIP')">
          <button
            type="button"
            class="inline-flex items-center justify-center p-0 rounded-md text-n-slate-11 hover:text-n-slate-12"
            @click="view = 'main'"
          >
            <span class="i-lucide-arrow-left text-xl" />
          </button>
        </Tooltip>
        <h3 class="text-base font-semibold text-n-slate-12">{{ headerTitle }}</h3>
      </header>

      <!-- ── Sub-view: Arquivos ────────────────────────────────────── -->
      <FilesPanel
        v-if="view === 'files'"
        :room-id="Number(room.id)"
      />

      <!-- ── Sub-view: Favoritos ───────────────────────────────────── -->
      <FavoritesPanel
        v-else-if="view === 'favorites'"
        :room-id="Number(room.id)"
        @jump-to-message="(id) => { emit('jump-to-message', id); emit('close'); }"
      />

      <!-- ── View principal ────────────────────────────────────────── -->
      <div v-else class="flex flex-col flex-1 overflow-y-auto ic-thread-scroll">
        <!-- Hero: avatar grande + nome + presença -->
        <section class="flex flex-col items-center px-6 py-8 border-b border-n-weak">
          <div class="relative">
            <!-- Cadeia de fallback pro src:
                 1. `room.avatar_url` — sempre presente, backend espelha o do User
                 2. `otherUser.thumbnail` — campo do agent serializer Chatwoot
                    (_agent.json.jbuilder retorna `thumbnail`, NÃO `avatar_url`)
                 3. `otherUser.avatar_url` — fallback caso o serializer mude -->
            <Avatar
              :name="displayName"
              :src="room?.avatar_url || otherUser?.thumbnail || otherUser?.avatar_url || ''"
              :size="96"
              rounded-full
            />
            <PresenceDot
              :user-id="Number(otherUserId)"
              :size="14"
              class="absolute bottom-1 right-1 ring-2 ring-n-solid-1 rounded-full"
            />
          </div>
          <h2 class="mt-4 text-lg font-semibold text-center text-n-slate-12">
            {{ displayName }}
          </h2>
          <p class="mt-1 text-sm font-medium" :class="presenceColor">
            {{ presenceLabel }}
          </p>
        </section>

        <!-- Informações: email + role -->
        <section class="px-5 py-4 border-b border-n-weak">
          <h4 class="mb-3 text-[11px] font-semibold tracking-wider uppercase text-n-slate-10">
            {{ $t('INTERNAL_CHAT.DM_DRAWER.SECTION_INFO') }}
          </h4>
          <ul class="space-y-3">
            <li class="flex items-start gap-3">
              <span class="i-lucide-mail text-base text-n-slate-11 shrink-0 mt-0.5" />
              <div class="flex-1 min-w-0">
                <p class="text-[11px] uppercase tracking-wider text-n-slate-10">
                  {{ $t('INTERNAL_CHAT.DM_DRAWER.EMAIL_LABEL') }}
                </p>
                <p class="text-sm break-all text-n-slate-12">
                  {{ emailValue || $t('INTERNAL_CHAT.DM_DRAWER.EMAIL_EMPTY') }}
                </p>
              </div>
            </li>
            <li class="flex items-start gap-3">
              <span class="i-lucide-shield-check text-base text-n-slate-11 shrink-0 mt-0.5" />
              <div class="flex-1 min-w-0">
                <p class="text-[11px] uppercase tracking-wider text-n-slate-10">
                  {{ $t('INTERNAL_CHAT.DM_DRAWER.ROLE_LABEL') }}
                </p>
                <p class="text-sm text-n-slate-12">{{ roleLabel }}</p>
              </div>
            </li>
          </ul>
        </section>

        <!-- Quick links: arquivos + favoritos -->
        <section class="px-5 py-4 border-b border-n-weak">
          <h4 class="mb-3 text-[11px] font-semibold tracking-wider uppercase text-n-slate-10">
            {{ $t('INTERNAL_CHAT.DM_DRAWER.SECTION_QUICK_LINKS') }}
          </h4>
          <button
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2.5 -mx-1 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1 transition"
            @click="view = 'files'"
          >
            <span class="i-lucide-paperclip text-lg text-n-slate-11" />
            <span class="flex-1 text-start">{{ $t('INTERNAL_CHAT.DM_DRAWER.OPEN_FILES') }}</span>
            <span class="i-lucide-chevron-right text-base text-n-slate-10" />
          </button>
          <button
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2.5 -mx-1 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1 transition"
            @click="view = 'favorites'"
          >
            <span class="i-lucide-star text-lg text-n-slate-11" />
            <span class="flex-1 text-start">{{ $t('INTERNAL_CHAT.DM_DRAWER.OPEN_FAVORITES') }}</span>
            <span class="i-lucide-chevron-right text-base text-n-slate-10" />
          </button>
        </section>

        <!-- Ações: silenciar + arquivar -->
        <section class="px-5 py-4">
          <h4 class="mb-3 text-[11px] font-semibold tracking-wider uppercase text-n-slate-10">
            {{ $t('INTERNAL_CHAT.DM_DRAWER.SECTION_ACTIONS') }}
          </h4>
          <button
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2.5 -mx-1 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1 transition disabled:opacity-50"
            :disabled="isMutating"
            @click="toggleMute"
          >
            <span :class="isMuted ? 'i-lucide-bell' : 'i-lucide-bell-off'" class="text-lg text-n-slate-11" />
            <span class="flex-1 text-start">
              <span class="block">
                {{ isMuted
                    ? $t('INTERNAL_CHAT.DM_DRAWER.UNMUTE')
                    : $t('INTERNAL_CHAT.DM_DRAWER.MUTE') }}
              </span>
              <span v-if="isMuted" class="block mt-0.5 text-xs text-n-slate-10">
                {{ $t('INTERNAL_CHAT.DM_DRAWER.MUTED_HINT', { time: muteUntilLabel }) }}
              </span>
            </span>
          </button>
          <button
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2.5 -mx-1 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1 transition disabled:opacity-50"
            :disabled="isMutating"
            @click="toggleArchive"
          >
            <span :class="isArchived ? 'i-lucide-archive-restore' : 'i-lucide-archive'" class="text-lg text-n-slate-11" />
            <span class="flex-1 text-start">
              {{ isArchived
                  ? $t('INTERNAL_CHAT.DM_DRAWER.UNARCHIVE')
                  : $t('INTERNAL_CHAT.DM_DRAWER.ARCHIVE') }}
            </span>
          </button>
          <p v-if="isArchived" class="px-3 mt-2 text-xs text-n-slate-10">
            {{ $t('INTERNAL_CHAT.DM_DRAWER.ARCHIVED_HINT') }}
          </p>
        </section>
      </div>
    </aside>
  </div>
</template>
