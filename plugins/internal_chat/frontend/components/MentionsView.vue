<script setup>
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.MENTIONS_VIEW.*` via i18n. `formatDate` continua usando
// API nativa do navegador (`toLocaleString('pt-BR', ...)`) — locale data
// não é string hardcoded da UI.
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-8: BeclinicButton para ação "Marcar tudo como lido" no header.
// Filter pills e itens da lista permanecem nativos (visual rounded-full / row
// custom com avatar+texto+dot indicator).
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
// PERF-25 (auditoria 2026-05-19): virtualização pra histórico longo de
// menções. DynamicScroller (não Recycle) porque content_preview varia
// — line-clamp-2 mantém máx 2 linhas mas mensagens curtas ocupam menos.
import { DynamicScroller, DynamicScrollerItem } from 'vue-virtual-scroller';
import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';

const store = useStore();
const route = useRoute();
const router = useRouter();
const filter = ref('unread'); // unread | all

const items = computed(() => store.getters['internalChatMentions/getAll']);
const isFetching = computed(
  () => store.getters['internalChatMentions/getUIFlags'].isFetching
);

const fetchAll = () => store.dispatch('internalChatMentions/fetch', { status: filter.value });

onMounted(fetchAll);

const formatDate = ts => {
  if (!ts) return '';
  const d = new Date(ts);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const goTo = mention => {
  router.push({
    name: 'internal_chat_room',
    params: { accountId: route.params.accountId, roomId: mention.room_id },
    hash: `#msg-${mention.message_id}`,
  });
  if (!mention.read_at) {
    store.dispatch('internalChatMentions/markRead', [mention.message_id]);
  }
};

const markAll = async () => {
  await store.dispatch('internalChatMentions/markRead', null);
  fetchAll();
};

const setFilter = f => {
  filter.value = f;
  fetchAll();
};

// Mobile: voltar pra lista de salas (no mobile a sidebar fica escondida
// enquanto Menções está aberto, então sem este botão o user fica preso).
const goBackToList = () => {
  router.push({
    name: 'internal_chat_home',
    params: { accountId: route.params.accountId },
  });
};
</script>

<template>
  <div class="flex flex-col flex-1 h-full bg-n-background">
    <header
      class="flex items-center justify-between gap-2 px-3 md:px-5 h-[60px] border-b border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center gap-2 min-w-0">
        <!-- Mobile: voltar pra lista de salas. Some em md+. -->
        <button
          type="button"
          class="md:hidden inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition shrink-0"
          @click="goBackToList"
        >
          <span class="i-lucide-arrow-left text-xl" />
        </button>
        <div class="leading-tight min-w-0">
          <h2 class="text-base font-semibold text-n-slate-12 truncate">
            {{ $t('INTERNAL_CHAT.MENTIONS_VIEW.TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11 mt-0.5 truncate">
            {{ $t('INTERNAL_CHAT.MENTIONS_VIEW.SUBTITLE') }}
          </p>
        </div>
      </div>
      <BeclinicButton
        :label="$t('INTERNAL_CHAT.MENTIONS_VIEW.MARK_ALL_READ')"
        variant="ghost"
        color="slate"
        size="sm"
        @click="markAll"
      />
    </header>

    <div class="flex gap-2 px-5 py-2 border-b border-n-weak">
      <button
        type="button"
        class="px-3 py-1 text-xs font-medium rounded-full transition"
        :class="
          filter === 'unread'
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-1 text-n-slate-11 hover:text-n-slate-12'
        "
        @click="setFilter('unread')"
      >
        {{ $t('INTERNAL_CHAT.MENTIONS_VIEW.FILTER_UNREAD') }}
      </button>
      <button
        type="button"
        class="px-3 py-1 text-xs font-medium rounded-full transition"
        :class="
          filter === 'all'
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-1 text-n-slate-11 hover:text-n-slate-12'
        "
        @click="setFilter('all')"
      >
        {{ $t('INTERNAL_CHAT.MENTIONS_VIEW.FILTER_ALL') }}
      </button>
    </div>

    <div
      v-if="isFetching && items.length === 0"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ $t('INTERNAL_CHAT.MENTIONS_VIEW.LOADING') }}
    </div>

    <div
      v-else-if="items.length === 0"
      class="flex flex-col items-center justify-center flex-1 text-center px-6"
    >
      <span class="i-lucide-at-sign text-5xl mb-3 text-n-slate-8" />
      <p class="text-sm text-n-slate-11">
        {{
          filter === 'unread'
            ? $t('INTERNAL_CHAT.MENTIONS_VIEW.EMPTY_UNREAD')
            : $t('INTERNAL_CHAT.MENTIONS_VIEW.EMPTY_ALL')
        }}
      </p>
    </div>

    <!-- PERF-25: DynamicScroller pra items com altura variável (1 ou 2
         linhas de content_preview). `min-item-size=72` casa com row de
         1 linha; DynamicScrollerItem mede e ajusta automaticamente. -->
    <DynamicScroller
      v-else
      class="flex-1 ic-thread-scroll"
      :items="items"
      :min-item-size="72"
      key-field="id"
    >
      <template #default="{ item, index, active }">
        <DynamicScrollerItem
          :item="item"
          :active="active"
          :data-index="index"
          :size-dependencies="[item.content_preview, item.read_at]"
        >
          <!-- Wrapper externo gera margem lateral (px-3) + vertical (mt-1)
               pra cada item virar um "cartão" com respiro nas bordas, em
               vez da linha edge-to-edge antiga. Botão interno fica rounded
               e perde o border-b (separação visual agora é pelo gap). -->
          <div class="px-3 pt-1">
            <button
              type="button"
              class="flex items-start w-full gap-3 px-3 py-2.5 transition rounded-lg text-start hover:bg-n-alpha-1"
              :class="!item.read_at ? 'bg-n-alpha-1' : ''"
              @click="goTo(item)"
            >
              <Avatar
                :name="item.sender?.name || $t('INTERNAL_CHAT.MENTIONS_VIEW.USER_FALLBACK_NAME')"
                :src="item.sender?.avatar_url || ''"
                :size="36"
                rounded-full
              />
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between gap-2">
                <p class="text-sm font-medium truncate text-n-slate-12 leading-tight">
                  {{ item.sender?.name || $t('INTERNAL_CHAT.MENTIONS_VIEW.USER_FALLBACK_NAME') }}
                  <span class="text-xs font-normal text-n-slate-11">
                    {{
                      $t('INTERNAL_CHAT.MENTIONS_VIEW.IN_ROOM_LABEL', {
                        room: item.room_name || $t('INTERNAL_CHAT.MENTIONS_VIEW.ROOM_FALLBACK_NAME'),
                      })
                    }}
                  </span>
                </p>
                <span class="text-[11px] text-n-slate-10 shrink-0">
                  {{ formatDate(item.created_at) }}
                </span>
              </div>
              <p class="mt-1 text-xs text-n-slate-11 line-clamp-2 leading-tight">
                {{ item.content_preview || $t('INTERNAL_CHAT.MENTIONS_VIEW.PREVIEW_EMPTY') }}
              </p>
            </div>
            <span
              v-if="!item.read_at"
              class="self-center w-2 h-2 rounded-full bg-n-brand shrink-0"
            />
            </button>
          </div>
        </DynamicScrollerItem>
      </template>
    </DynamicScroller>
  </div>
</template>
