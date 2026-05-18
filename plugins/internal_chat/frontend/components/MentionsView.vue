<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

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
</script>

<template>
  <div class="flex flex-col flex-1 h-full bg-n-background">
    <header
      class="flex items-center justify-between px-5 py-3 border-b border-n-weak bg-n-solid-1"
    >
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">Menções</h2>
        <p class="text-xs text-n-slate-11">Mensagens que mencionaram você</p>
      </div>
      <button
        type="button"
        class="px-3 py-1.5 text-xs font-medium rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
        @click="markAll"
      >
        Marcar todas como lidas
      </button>
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
        Não lidas
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
        Todas
      </button>
    </div>

    <div
      v-if="isFetching && items.length === 0"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      Carregando…
    </div>

    <div
      v-else-if="items.length === 0"
      class="flex flex-col items-center justify-center flex-1 text-center px-6"
    >
      <span class="i-lucide-at-sign text-5xl mb-3 text-n-slate-8" />
      <p class="text-sm text-n-slate-11">
        {{ filter === 'unread' ? 'Sem menções não lidas' : 'Nenhuma menção ainda' }}
      </p>
    </div>

    <ul v-else class="flex-1 overflow-y-auto ic-thread-scroll">
      <li
        v-for="m in items"
        :key="m.id"
      >
        <button
          type="button"
          class="flex items-start w-full gap-3 px-5 py-3 transition border-b border-n-weak text-start hover:bg-n-alpha-1"
          :class="!m.read_at ? 'bg-n-alpha-1' : ''"
          @click="goTo(m)"
        >
          <Avatar
            :name="m.sender?.name || 'Usuário'"
            :size="36"
            rounded-full
          />
          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between gap-2">
              <p class="text-sm font-medium truncate text-n-slate-12">
                {{ m.sender?.name || 'Usuário' }}
                <span class="text-xs font-normal text-n-slate-11">
                  em {{ m.room_name || 'conversa' }}
                </span>
              </p>
              <span class="text-[11px] text-n-slate-10 shrink-0">
                {{ formatDate(m.created_at) }}
              </span>
            </div>
            <p class="text-xs text-n-slate-11 line-clamp-2 mt-0.5">
              {{ m.content_preview || '(sem prévia)' }}
            </p>
          </div>
          <span
            v-if="!m.read_at"
            class="self-center w-2 h-2 rounded-full bg-n-brand shrink-0"
          />
        </button>
      </li>
    </ul>
  </div>
</template>
