<script setup>
// FE-16/17 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.NEW_ROOM.*` via i18n. Comportamento, classes Tailwind,
// props e emits preservados 1:1.
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-8: BeclinicButton no footer (Cancelar/Criar) e Checkbox para "adicionar Bea".
// Tabs no header e list-items com avatar+toggle permanecem nativos.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
// FE-X: SearchInput padrão do beclinic_core — substitui input cru + ícone
// absoluto (que tinha overlap visual quando text digitado encostava no
// ícone à esquerda). Componente compartilhado já trata posicionamento.
import SearchInput from '@plugins/beclinic_core/frontend/components/SearchInput.vue';

const emit = defineEmits(['close']);

const store = useStore();
const route = useRoute();
const router = useRouter();

const tab = ref('direct'); // direct | group
const search = ref('');
const groupName = ref('');
const selected = ref(new Set());
const addBea = ref(false);
const isSubmitting = ref(false);

const currentUserId = computed(() => store.getters.getCurrentUserID);
const agents = computed(() =>
  (store.getters['agents/getAgents'] || []).filter(
    a => a.id !== currentUserId.value && a.confirmed
  )
);

const filtered = computed(() => {
  if (!search.value) return agents.value;
  const q = search.value.toLowerCase();
  return agents.value.filter(a => (a.name || '').toLowerCase().includes(q));
});

onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
});

const toggle = id => {
  if (tab.value === 'direct') {
    selected.value = new Set([id]);
  } else if (selected.value.has(id)) {
    selected.value.delete(id);
    selected.value = new Set(selected.value);
  } else {
    selected.value.add(id);
    selected.value = new Set(selected.value);
  }
};

const canSubmit = computed(() => {
  if (selected.value.size === 0) return false;
  if (tab.value === 'group' && !groupName.value.trim()) return false;
  return !isSubmitting.value;
});

const submit = async () => {
  if (!canSubmit.value) return;
  isSubmitting.value = true;
  try {
    const payload = {
      kind: tab.value,
      member_user_ids: Array.from(selected.value),
    };
    if (tab.value === 'group') {
      payload.name = groupName.value.trim();
      if (addBea.value) payload.add_bea = true;
    }
    const room = await store.dispatch('internalChatRooms/create', payload);
    emit('close');
    router.push({
      name: 'internal_chat_room',
      params: { accountId: route.params.accountId, roomId: room.id },
    });
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <!-- Teleport pra <body>: garante que o overlay cubra TODA a viewport
       (inclusive a sidebar global "Mamedes"). Sem teleport o `fixed inset-0`
       fica preso a algum ancestral com `transform`/`filter` e o backdrop
       não aparece sobre o app inteiro.
       Backdrop NÃO fecha o modal (memória `feedback_modal_no_backdrop_close`)
       — só os botões Cancelar/Criar/X. Evita perder dados em formulário longo. -->
  <Teleport to="body">
    <!-- `ic-app` re-aplicado: Teleport tira o modal do DOM do ChatShell,
         então o scope do reset de margens não chega via herança. -->
    <div
      class="ic-app fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/50"
    >
    <div
      class="w-full max-w-lg rounded-xl bg-n-solid-1 border border-n-weak shadow-2xl flex flex-col max-h-[85vh] overflow-hidden"
    >
      <header class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
        <h3 class="text-base font-semibold text-n-slate-12">{{ $t('INTERNAL_CHAT.NEW_ROOM.TITLE') }}</h3>
        <button
          type="button"
          class="text-n-slate-11 hover:text-n-slate-12"
          :aria-label="$t('INTERNAL_CHAT.NEW_ROOM.CLOSE_TOOLTIP')"
          @click="emit('close')"
        >
          <span class="i-lucide-x text-xl" />
        </button>
      </header>

      <div class="flex border-b border-n-weak">
        <button
          v-for="tabKey in ['direct', 'group']"
          :key="tabKey"
          type="button"
          class="flex-1 px-4 py-2.5 text-sm font-medium transition"
          :class="
            tab === tabKey
              ? 'text-n-brand border-b-2 border-n-brand'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="tab = tabKey; selected = new Set(); addBea = false"
        >
          {{ tabKey === 'direct' ? $t('INTERNAL_CHAT.NEW_ROOM.TAB_DIRECT') : $t('INTERNAL_CHAT.NEW_ROOM.TAB_GROUP') }}
        </button>
      </div>

      <div v-if="tab === 'group'" class="px-5 pt-4">
        <input
          v-model="groupName"
          type="text"
          :placeholder="$t('INTERNAL_CHAT.NEW_ROOM.GROUP_NAME_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
        >
        <Checkbox v-model="addBea" class="mt-3 px-1 items-start">
          <span class="text-sm text-n-slate-12 leading-tight">
            {{ $t('INTERNAL_CHAT.NEW_ROOM.ADD_BEA_LABEL') }}
            <span class="block text-xs text-n-slate-10 mt-0.5 font-normal">
              {{ $t('INTERNAL_CHAT.NEW_ROOM.ADD_BEA_HINT') }}
            </span>
          </span>
        </Checkbox>
      </div>

      <div class="px-5 py-3">
        <SearchInput
          v-model="search"
          class="ic-newroom-search"
          :placeholder="$t('INTERNAL_CHAT.NEW_ROOM.SEARCH_PLACEHOLDER')"
        />
      </div>

      <ul class="flex-1 px-2 pb-2 overflow-y-auto ic-thread-scroll">
        <li v-if="filtered.length === 0" class="px-3 py-6 text-sm text-center text-n-slate-11">
          {{ $t('INTERNAL_CHAT.NEW_ROOM.EMPTY') }}
        </li>
        <li
          v-for="agent in filtered"
          :key="agent.id"
        >
          <button
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2 text-start rounded-md hover:bg-n-alpha-1 transition"
            :class="selected.has(agent.id) ? 'bg-n-alpha-2' : ''"
            @click="toggle(agent.id)"
          >
            <!-- Chatwoot agent serializer (`_agent.json.jbuilder`) expõe
                 avatar como `thumbnail`, NÃO `avatar_url`. Mantém fallback
                 pra `avatar_url` caso o backend mude no futuro. -->
            <Avatar :name="agent.name" :src="agent.thumbnail || agent.avatar_url || ''" :size="36" rounded-full />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium truncate text-n-slate-12">{{ agent.name }}</p>
              <p class="text-xs truncate text-n-slate-11">{{ agent.email }}</p>
            </div>
            <span
              class="w-5 h-5 rounded-full border flex items-center justify-center"
              :class="selected.has(agent.id) ? 'bg-n-brand border-n-brand' : 'border-n-slate-7'"
            >
              <span v-if="selected.has(agent.id)" class="i-lucide-check text-white text-sm" />
            </span>
          </button>
        </li>
      </ul>

      <footer class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak">
        <BeclinicButton
          :label="$t('INTERNAL_CHAT.NEW_ROOM.CANCEL')"
          variant="outline"
          color="slate"
          size="sm"
          @click="emit('close')"
        />
        <BeclinicButton
          :label="isSubmitting ? $t('INTERNAL_CHAT.NEW_ROOM.SUBMIT_CREATING') : $t('INTERNAL_CHAT.NEW_ROOM.SUBMIT_CREATE')"
          :is-loading="isSubmitting"
          :disabled="!canSubmit"
          size="sm"
          @click="submit"
        />
      </footer>
    </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
/* SearchInput por padrão clamp 220-380px — aqui dentro do modal de ~512px
   queremos full width pra casar com a lista de agentes abaixo. */
.ic-newroom-search {
  min-width: 0;
  max-width: none;
  width: 100%;
}
</style>
