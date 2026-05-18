<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

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
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-lg rounded-xl bg-n-solid-1 border border-n-weak shadow-2xl flex flex-col max-h-[85vh] overflow-hidden"
    >
      <header class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
        <h3 class="text-base font-semibold text-n-slate-12">Nova conversa</h3>
        <button
          type="button"
          class="text-n-slate-11 hover:text-n-slate-12"
          @click="emit('close')"
        >
          <span class="i-lucide-x text-xl" />
        </button>
      </header>

      <div class="flex border-b border-n-weak">
        <button
          v-for="t in ['direct', 'group']"
          :key="t"
          type="button"
          class="flex-1 px-4 py-2.5 text-sm font-medium transition"
          :class="
            tab === t
              ? 'text-n-brand border-b-2 border-n-brand'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="tab = t; selected = new Set(); addBea = false"
        >
          {{ t === 'direct' ? 'Direta (1:1)' : 'Grupo' }}
        </button>
      </div>

      <div v-if="tab === 'group'" class="px-5 pt-4">
        <input
          v-model="groupName"
          type="text"
          placeholder="Nome do grupo"
          class="w-full px-3 py-2 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
        >
        <label class="flex items-start gap-2.5 mt-3 px-1 cursor-pointer select-none">
          <input
            v-model="addBea"
            type="checkbox"
            class="mt-0.5 w-4 h-4 rounded border-n-slate-7 text-n-brand focus:ring-n-brand"
          >
          <span class="text-sm text-n-slate-12 leading-tight">
            Adicionar Beatriz · IA ao grupo
            <span class="block text-xs text-n-slate-10 mt-0.5 font-normal">
              Permite mencionar @beatriz e usar este grupo como destino de avisos automáticos.
            </span>
          </span>
        </label>
      </div>

      <div class="px-5 py-3">
        <div class="relative">
          <span class="absolute -translate-y-1/2 i-lucide-search left-3 top-1/2 text-n-slate-10" />
          <input
            v-model="search"
            type="text"
            placeholder="Buscar profissional..."
            class="w-full py-2 pl-9 pr-3 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
          >
        </div>
      </div>

      <ul class="flex-1 px-2 pb-2 overflow-y-auto ic-thread-scroll">
        <li v-if="filtered.length === 0" class="px-3 py-6 text-sm text-center text-n-slate-11">
          Nenhum profissional encontrado
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
            <Avatar :name="agent.name" :src="agent.avatar_url || ''" :size="36" rounded-full />
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
        <button
          type="button"
          class="px-4 py-2 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1"
          @click="emit('close')"
        >
          Cancelar
        </button>
        <button
          type="button"
          class="px-4 py-2 text-sm rounded-md bg-n-brand text-white disabled:opacity-50 disabled:cursor-not-allowed hover:brightness-110"
          :disabled="!canSubmit"
          @click="submit"
        >
          {{ isSubmitting ? 'Criando…' : 'Criar conversa' }}
        </button>
      </footer>
    </div>
  </div>
</template>
