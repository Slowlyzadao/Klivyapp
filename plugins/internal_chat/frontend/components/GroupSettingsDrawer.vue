<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import FavoritesPanel from './FavoritesPanel.vue';
import FilesPanel from './FilesPanel.vue';

const props = defineProps({
  room: { type: Object, required: true },
  initialTab: { type: String, default: 'members' }, // 'members' | 'edit' | 'favorites' | 'files'
});
const emit = defineEmits(['close', 'jump-to-message']);

const store = useStore();
const route = useRoute();
const router = useRouter();

// Estilo WhatsApp: drawer tem uma view principal (avatar/nome/descrição/membros)
// e duas sub-views (arquivos / favoritos) que se abrem com botão voltar.
const view = ref(
  props.initialTab === 'files'
    ? 'files'
    : props.initialTab === 'favorites'
      ? 'favorites'
      : 'main'
);

// Edição inline do nome/descrição (não usa mais aba "Detalhes" separada).
const editingField = ref(null); // 'name' | 'description' | null
const editName = ref(props.room.name || '');
const editDescription = ref(props.room.description || '');
const isSaving = ref(false);
const isUploadingAvatar = ref(false);
const isDeletingGroup = ref(false);
const showAddMember = ref(false);
const search = ref('');
const avatarInputRef = ref(null);

watch(
  () => props.room,
  r => {
    if (editingField.value !== 'name') editName.value = r?.name || '';
    if (editingField.value !== 'description') editDescription.value = r?.description || '';
  }
);

const currentUserId = computed(() => store.getters.getCurrentUserID);
const currentMembership = computed(() =>
  props.room.members?.find(m => m.user_id === currentUserId.value)
);
const canManage = computed(() => {
  const role = currentMembership.value?.role;
  return role === 'owner' || role === 'admin';
});
// Só o criador do grupo pode excluí-lo (e admins de conta — backend valida).
const isOwner = computed(
  () => props.room.created_by_user_id === currentUserId.value
);

const allAgents = computed(() => store.getters['agents/getAgents'] || []);
const candidates = computed(() => {
  const memberIds = new Set(
    (props.room.members || []).filter(m => m.user_id).map(m => m.user_id)
  );
  const list = allAgents.value.filter(
    a => !memberIds.has(a.id) && a.confirmed && a.id !== currentUserId.value
  );
  if (!search.value) return list;
  const q = search.value.toLowerCase();
  return list.filter(a => (a.name || '').toLowerCase().includes(q));
});

const hasBea = computed(() =>
  (props.room.members || []).some(m => m.is_ai)
);

const headerTitle = computed(() => {
  if (view.value === 'files') return 'Arquivos';
  if (view.value === 'favorites') return 'Mensagens favoritas';
  return 'Dados do grupo';
});

const memberRole = m => {
  if (m.is_ai) return 'IA agêntica';
  if (m.role === 'owner') return 'Criador do grupo';
  if (m.role === 'admin') return 'Admin do grupo';
  return 'Membro';
};

const startEdit = field => {
  if (!canManage.value) return;
  if (field === 'name') editName.value = props.room.name || '';
  if (field === 'description') editDescription.value = props.room.description || '';
  editingField.value = field;
};
const cancelEdit = () => {
  editingField.value = null;
  editName.value = props.room.name || '';
  editDescription.value = props.room.description || '';
};
const saveEdit = async () => {
  await saveDetails();
  editingField.value = null;
};

const saveDetails = async () => {
  if (!canManage.value) return;
  isSaving.value = true;
  try {
    await store.dispatch('internalChatRooms/update', {
      id: props.room.id,
      name: editName.value.trim(),
      description: editDescription.value.trim(),
    });
  } finally {
    isSaving.value = false;
  }
};

const addMember = async userId => {
  await store.dispatch('internalChatRooms/addMember', {
    roomId: props.room.id,
    userId,
  });
  showAddMember.value = false;
  search.value = '';
};

const addBea = async () => {
  await store.dispatch('internalChatRooms/addBeaMember', {
    roomId: props.room.id,
  });
};

const removeMember = async membershipId => {
  if (!confirm('Remover este membro do grupo?')) return;
  await store.dispatch('internalChatRooms/removeMember', {
    roomId: props.room.id,
    membershipId,
  });
};

const promote = async (membershipId, role) => {
  await store.dispatch('internalChatRooms/changeMemberRole', {
    roomId: props.room.id,
    membershipId,
    role,
  });
};

const onAvatarPick = async e => {
  const file = e.target.files?.[0];
  e.target.value = '';
  if (!file || !canManage.value) return;
  if (!/^image\/(jpe?g|png|gif|webp)$/i.test(file.type)) {
    alert('Use uma imagem JPG, PNG, GIF ou WEBP.');
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    alert('A imagem precisa ter no máximo 5MB.');
    return;
  }
  isUploadingAvatar.value = true;
  try {
    await store.dispatch('internalChatRooms/updateAvatar', {
      roomId: props.room.id,
      file,
    });
  } catch {
    alert('Falha ao enviar imagem do grupo.');
  } finally {
    isUploadingAvatar.value = false;
  }
};

const removeAvatar = async () => {
  if (!canManage.value) return;
  if (!confirm('Remover a imagem do grupo?')) return;
  isUploadingAvatar.value = true;
  try {
    await store.dispatch('internalChatRooms/removeAvatar', props.room.id);
  } finally {
    isUploadingAvatar.value = false;
  }
};

const deleteGroup = async () => {
  if (!isOwner.value) return;
  const confirmText = `Excluir o grupo "${props.room.name}" para todos os membros? Esta ação não pode ser desfeita.`;
  if (!confirm(confirmText)) return;
  isDeletingGroup.value = true;
  try {
    await store.dispatch('internalChatRooms/destroy', props.room.id);
    emit('close');
    router.push({
      name: 'internal_chat_home',
      params: { accountId: route.params.accountId },
    });
  } catch {
    alert('Falha ao excluir o grupo.');
  } finally {
    isDeletingGroup.value = false;
  }
};

const leave = async () => {
  if (!confirm('Tem certeza que deseja sair deste grupo?')) return;
  await store.dispatch('internalChatRooms/leaveRoom', {
    roomId: props.room.id,
    membershipId: currentMembership.value.id,
  });
  emit('close');
  router.push({
    name: 'internal_chat_home',
    params: { accountId: route.params.accountId },
  });
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-end bg-black/40"
    @click.self="emit('close')"
  >
    <aside
      class="flex flex-col w-full h-full max-w-md overflow-hidden border-l shadow-2xl bg-n-solid-1 border-n-weak"
    >
      <!-- Header: X / voltar + título dinâmico (estilo WhatsApp) -->
      <header class="flex items-center gap-3 px-4 py-3 border-b border-n-weak shrink-0">
        <button
          v-if="view === 'main'"
          type="button"
          class="inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          title="Fechar"
          @click="emit('close')"
        >
          <span class="i-lucide-x text-xl" />
        </button>
        <button
          v-else
          type="button"
          class="inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          title="Voltar"
          @click="view = 'main'"
        >
          <span class="i-lucide-arrow-left text-xl" />
        </button>
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ headerTitle }}
        </h3>
      </header>

      <!-- Sub-view: Arquivos -->
      <FilesPanel
        v-if="view === 'files'"
        :room-id="Number(room.id)"
      />

      <!-- Sub-view: Favoritos -->
      <FavoritesPanel
        v-else-if="view === 'favorites'"
        :room-id="Number(room.id)"
        @jump-to-message="(id) => { emit('jump-to-message', id); emit('close'); }"
      />

      <!-- View principal -->
      <div v-else class="flex flex-col flex-1 overflow-y-auto ic-thread-scroll">
        <!-- Hero: avatar grande + nome + descrição (estilo WhatsApp) -->
        <section class="flex flex-col items-center gap-3 px-5 py-6 border-b border-n-weak">
          <div class="relative">
            <Avatar
              :name="room.name || 'Grupo'"
              :src="room.avatar_url || ''"
              :size="120"
              rounded-full
            />
            <button
              v-if="canManage"
              type="button"
              class="absolute bottom-0 right-0 inline-flex items-center justify-center w-9 h-9 rounded-full bg-n-brand text-white shadow hover:brightness-110 disabled:opacity-50"
              title="Trocar imagem"
              :disabled="isUploadingAvatar"
              @click="avatarInputRef.click()"
            >
              <span class="i-lucide-camera text-base" />
            </button>
          </div>
          <input
            ref="avatarInputRef"
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            class="hidden"
            @change="onAvatarPick"
          >
          <button
            v-if="canManage && room.avatar_url"
            type="button"
            class="text-xs text-n-slate-11 hover:text-n-ruby-11 disabled:opacity-50"
            :disabled="isUploadingAvatar"
            @click="removeAvatar"
          >
            Remover imagem
          </button>

          <!-- Nome — clica no lápis pra editar inline -->
          <div class="flex items-center gap-2 max-w-full mt-2">
            <template v-if="editingField === 'name'">
              <input
                v-model="editName"
                type="text"
                class="px-3 py-1.5 text-lg font-semibold text-center rounded-md bg-n-alpha-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :disabled="isSaving"
                autofocus
                @keydown.enter.prevent="saveEdit"
                @keydown.escape.prevent="cancelEdit"
              >
              <button
                type="button"
                class="inline-flex items-center justify-center w-7 h-7 rounded-md text-n-brand hover:bg-n-brand/10 disabled:opacity-50"
                title="Salvar"
                :disabled="isSaving || !editName.trim()"
                @click="saveEdit"
              >
                <span class="i-lucide-check text-base" />
              </button>
              <button
                type="button"
                class="inline-flex items-center justify-center w-7 h-7 rounded-md text-n-slate-11 hover:bg-n-alpha-1"
                title="Cancelar"
                :disabled="isSaving"
                @click="cancelEdit"
              >
                <span class="i-lucide-x text-base" />
              </button>
            </template>
            <template v-else>
              <h2 class="text-xl font-semibold truncate text-n-slate-12">
                {{ room.name || 'Grupo' }}
              </h2>
              <button
                v-if="canManage"
                type="button"
                class="inline-flex items-center justify-center w-7 h-7 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
                title="Editar nome"
                @click="startEdit('name')"
              >
                <span class="i-lucide-pencil text-sm" />
              </button>
            </template>
          </div>

          <p class="text-xs text-n-slate-10">
            Grupo · {{ room.members?.length || 0 }} {{ (room.members?.length || 0) === 1 ? 'membro' : 'membros' }}
          </p>
        </section>

        <!-- Descrição -->
        <section class="px-5 py-4 border-b border-n-weak">
          <div class="flex items-center justify-between mb-1.5">
            <p class="text-xs font-medium text-n-brand uppercase tracking-wide">
              Descrição
            </p>
            <button
              v-if="canManage && editingField !== 'description'"
              type="button"
              class="text-xs text-n-slate-11 hover:text-n-slate-12 inline-flex items-center gap-1"
              @click="startEdit('description')"
            >
              <span class="i-lucide-pencil text-xs" />
              Editar
            </button>
          </div>
          <template v-if="editingField === 'description'">
            <textarea
              v-model="editDescription"
              rows="3"
              class="w-full px-3 py-2 text-sm rounded-md resize-none bg-n-alpha-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :disabled="isSaving"
              autofocus
              placeholder="Adicione uma descrição ao grupo"
            />
            <div class="flex justify-end gap-2 mt-2">
              <button
                type="button"
                class="px-3 py-1.5 text-xs font-medium rounded-md text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
                :disabled="isSaving"
                @click="cancelEdit"
              >
                Cancelar
              </button>
              <button
                type="button"
                class="px-3 py-1.5 text-xs font-medium text-white rounded-md bg-n-brand hover:brightness-110 disabled:opacity-50"
                :disabled="isSaving"
                @click="saveEdit"
              >
                {{ isSaving ? 'Salvando…' : 'Salvar' }}
              </button>
            </div>
          </template>
          <p
            v-else
            class="text-sm whitespace-pre-wrap"
            :class="room.description ? 'text-n-slate-12' : 'text-n-slate-10 italic'"
          >
            {{ room.description || 'Sem descrição' }}
          </p>
        </section>

        <!-- Quick links (Arquivos / Favoritos) -->
        <section class="border-b border-n-weak py-1">
          <button
            type="button"
            class="flex items-center w-full gap-3 px-5 py-3 text-start hover:bg-n-alpha-1 transition"
            @click="view = 'files'"
          >
            <span class="i-lucide-folder text-lg text-n-slate-11" />
            <span class="flex-1 text-sm font-medium text-n-slate-12">Arquivos</span>
            <span class="i-lucide-chevron-right text-base text-n-slate-10" />
          </button>
          <button
            type="button"
            class="flex items-center w-full gap-3 px-5 py-3 text-start hover:bg-n-alpha-1 transition"
            @click="view = 'favorites'"
          >
            <span class="i-lucide-star text-lg text-n-slate-11" />
            <span class="flex-1 text-sm font-medium text-n-slate-12">Mensagens favoritas</span>
            <span class="i-lucide-chevron-right text-base text-n-slate-10" />
          </button>
        </section>

        <!-- Membros -->
        <section class="border-b border-n-weak">
          <p class="px-5 pt-4 pb-2 text-xs font-medium text-n-slate-11">
            {{ room.members?.length || 0 }} {{ (room.members?.length || 0) === 1 ? 'membro' : 'membros' }}
          </p>

          <button
            v-if="canManage"
            type="button"
            class="flex items-center w-full gap-3 px-5 py-2.5 text-start hover:bg-n-alpha-1 transition"
            @click="showAddMember = !showAddMember"
          >
            <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-brand/10 text-n-brand">
              <span class="i-lucide-user-plus text-base" />
            </span>
            <span class="text-sm font-medium text-n-brand">Adicionar membro</span>
          </button>

          <button
            v-if="canManage && !hasBea"
            type="button"
            class="flex items-center w-full gap-3 px-5 py-2.5 text-start hover:bg-n-alpha-1 transition"
            @click="addBea"
          >
            <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-brand/10 text-n-brand">
              <span class="i-lucide-sparkles text-base" />
            </span>
            <span class="text-sm font-medium text-n-brand">Adicionar Beatriz (IA)</span>
          </button>

          <!-- Search dropdown pra adicionar membro -->
          <div v-if="showAddMember && canManage" class="px-5 py-2">
            <input
              v-model="search"
              type="text"
              placeholder="Buscar profissional..."
              class="w-full px-3 py-2 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
            >
            <ul class="mt-2 max-h-[200px] overflow-y-auto ic-thread-scroll">
              <li v-if="candidates.length === 0" class="px-3 py-3 text-xs text-center text-n-slate-11">
                Sem candidatos
              </li>
              <li v-for="agent in candidates" :key="agent.id">
                <button
                  type="button"
                  class="flex items-center w-full gap-2 px-3 py-2 text-start rounded-md hover:bg-n-alpha-1"
                  @click="addMember(agent.id)"
                >
                  <Avatar :name="agent.name" :src="agent.avatar_url || ''" :size="28" rounded-full />
                  <span class="text-sm truncate text-n-slate-12">{{ agent.name }}</span>
                </button>
              </li>
            </ul>
          </div>

          <!-- Lista de membros -->
          <ul class="pb-2">
            <li
              v-for="m in room.members"
              :key="m.id"
              class="flex items-center gap-3 px-5 py-2 hover:bg-n-alpha-1 group transition"
            >
              <Avatar
                :name="m.name || 'Usuário'"
                :src="m.avatar_url || ''"
                :size="40"
                :icon-name="m.is_ai ? 'i-lucide-sparkles' : null"
                rounded-full
              />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium truncate text-n-slate-12 flex items-center gap-1.5">
                  <span class="truncate">{{ m.name }}</span>
                  <span v-if="m.user_id === currentUserId" class="text-xs font-normal text-n-slate-10">(você)</span>
                  <span
                    v-if="m.is_ai"
                    class="text-[9px] font-bold uppercase tracking-wide px-1 rounded bg-n-brand text-white shrink-0"
                  >
                    IA
                  </span>
                </p>
                <p class="text-xs text-n-slate-10 truncate">{{ memberRole(m) }}</p>
              </div>
              <span
                v-if="!m.is_ai && (m.role === 'owner' || m.role === 'admin')"
                class="text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded text-n-brand bg-n-brand/10 shrink-0"
              >
                {{ m.role === 'owner' ? 'Criador' : 'Admin' }}
              </span>
              <!-- Hover actions de gestão -->
              <div
                v-if="canManage && m.user_id !== currentUserId && m.role !== 'owner'"
                class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition shrink-0"
              >
                <button
                  v-if="!m.is_ai && m.role === 'member'"
                  type="button"
                  class="px-2 py-1 text-xs rounded text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  title="Promover a admin"
                  @click="promote(m.id, 'admin')"
                >
                  <span class="i-lucide-shield text-sm" />
                </button>
                <button
                  v-else-if="!m.is_ai && m.role === 'admin'"
                  type="button"
                  class="px-2 py-1 text-xs rounded text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  title="Rebaixar a membro"
                  @click="promote(m.id, 'member')"
                >
                  <span class="i-lucide-shield-off text-sm" />
                </button>
                <button
                  type="button"
                  class="px-2 py-1 text-xs rounded text-n-ruby-9 hover:bg-n-ruby-3"
                  :title="m.is_ai ? 'Remover Beatriz do grupo' : 'Remover do grupo'"
                  @click="removeMember(m.id)"
                >
                  <span class="i-lucide-x text-sm" />
                </button>
              </div>
            </li>
          </ul>
        </section>

        <!-- Danger zone -->
        <section class="py-2 mt-auto">
          <button
            v-if="currentMembership"
            type="button"
            class="flex items-center w-full gap-3 px-5 py-3 text-start text-n-ruby-11 hover:bg-n-ruby-3 transition"
            @click="leave"
          >
            <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-ruby-3 text-n-ruby-11">
              <span class="i-lucide-log-out text-base" />
            </span>
            <span class="text-sm font-medium">Sair do grupo</span>
          </button>
          <button
            v-if="isOwner"
            type="button"
            class="flex items-center w-full gap-3 px-5 py-3 text-start text-n-ruby-11 hover:bg-n-ruby-3 transition disabled:opacity-50"
            :disabled="isDeletingGroup"
            @click="deleteGroup"
          >
            <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-ruby-3 text-n-ruby-11">
              <span class="i-lucide-trash-2 text-base" />
            </span>
            <span class="text-sm font-medium">
              {{ isDeletingGroup ? 'Excluindo grupo…' : 'Excluir grupo' }}
            </span>
          </button>
        </section>
      </div>
    </aside>
  </div>
</template>
