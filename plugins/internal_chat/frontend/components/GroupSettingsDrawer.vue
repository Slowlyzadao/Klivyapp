<script setup>
// FE-2 (auditoria 2026-05-18): Drawer decomposto em sub-componentes:
//   - GroupSettingsHeader  (header com close/back + título)
//   - GroupHeroSection     (avatar + nome com edição inline + contador)
//   - GroupDescriptionSection (descrição com edição inline)
//   - GroupQuickLinks      (Arquivos / Favoritos)
//   - GroupMembersSection  (add + busca + lista + role mgmt)
//   - GroupDangerZone      (sair / excluir grupo)
// State + handlers + store dispatches PERMANECEM AQUI — filhos só recebem
// props e emitem eventos. Padrão idêntico ao FE-3/FE-4 (followUps/templates
// Index.vue).
//
// Decisões pragmáticas:
//   - `FilesPanel` / `FavoritesPanel` continuam usados direto (não criamos
//     wrapper GroupFavoritesTab.vue — não há lógica adicional que justifique).
//   - As ações destrutivas (remover membro/imagem, sair, excluir grupo) usam
//     ConfirmDangerModal + toast (useAlert) via um `confirmDialog` genérico —
//     migradas dos confirm()/alert() nativos.
//   - O `<input type="file">` foi movido pro GroupHeroSection (ref local).
//   - `memberRole(m)` foi duplicado no GroupMembersSection — formatador puro
//     de PT-BR, não vale criar util compartilhado.
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FavoritesPanel from './FavoritesPanel.vue';
import FilesPanel from './FilesPanel.vue';
import GroupSettingsHeader from './groupSettingsParts/GroupSettingsHeader.vue';
import GroupHeroSection from './groupSettingsParts/GroupHeroSection.vue';
import GroupDescriptionSection from './groupSettingsParts/GroupDescriptionSection.vue';
import GroupQuickLinks from './groupSettingsParts/GroupQuickLinks.vue';
import GroupMembersSection from './groupSettingsParts/GroupMembersSection.vue';
import GroupDangerZone from './groupSettingsParts/GroupDangerZone.vue';

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

// Confirmação genérica (ConfirmDangerModal) + toast — substitui os confirm()/
// alert() nativos das ações destrutivas (remover membro/imagem, sair, excluir).
// `run` é a ação async; successMsg/errorMsg viram toast.
const confirmDialog = ref(null);
const confirmBusy = ref(false);

const runConfirm = async () => {
  if (!confirmDialog.value) return;
  confirmBusy.value = true;
  try {
    await confirmDialog.value.run();
    if (confirmDialog.value?.successMsg) {
      useAlert(confirmDialog.value.successMsg);
    }
    confirmDialog.value = null;
  } catch (e) {
    useAlert(
      confirmDialog.value?.errorMsg || 'Não foi possível concluir a ação.'
    );
  } finally {
    confirmBusy.value = false;
  }
};

const closeConfirm = () => {
  if (confirmBusy.value) return;
  confirmDialog.value = null;
};

const removeMember = membershipId => {
  const m = (props.room.members || []).find(x => x.id === membershipId);
  const name = m?.name || 'Membro';
  confirmDialog.value = {
    title: 'Remover membro?',
    message: `${name} será removido do grupo e perde o acesso à conversa.`,
    confirmLabel: 'Remover',
    successMsg: `${name} removido do grupo.`,
    errorMsg: 'Falha ao remover o membro.',
    run: () =>
      store.dispatch('internalChatRooms/removeMember', {
        roomId: props.room.id,
        membershipId,
      }),
  };
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
    useAlert('Use uma imagem JPG, PNG, GIF ou WEBP.');
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    useAlert('A imagem precisa ter no máximo 5MB.');
    return;
  }
  isUploadingAvatar.value = true;
  try {
    await store.dispatch('internalChatRooms/updateAvatar', {
      roomId: props.room.id,
      file,
    });
    useAlert('Foto do grupo atualizada.');
  } catch {
    useAlert('Falha ao enviar imagem do grupo.');
  } finally {
    isUploadingAvatar.value = false;
  }
};

const removeAvatar = () => {
  if (!canManage.value) return;
  confirmDialog.value = {
    title: 'Remover imagem?',
    message: 'A foto do grupo será removida.',
    confirmLabel: 'Remover',
    successMsg: 'Imagem removida.',
    errorMsg: 'Falha ao remover a imagem.',
    run: () => store.dispatch('internalChatRooms/removeAvatar', props.room.id),
  };
};

const deleteGroup = () => {
  if (!isOwner.value) return;
  confirmDialog.value = {
    title: 'Excluir grupo?',
    message: `Excluir o grupo "${props.room.name}" para todos os membros? Esta ação não pode ser desfeita.`,
    confirmLabel: 'Excluir',
    successMsg: 'Grupo excluído.',
    errorMsg: 'Falha ao excluir o grupo.',
    run: async () => {
      await store.dispatch('internalChatRooms/destroy', props.room.id);
      emit('close');
      router.push({
        name: 'internal_chat_home',
        params: { accountId: route.params.accountId },
      });
    },
  };
};

const leave = () => {
  confirmDialog.value = {
    title: 'Sair do grupo?',
    message: 'Você deixará de receber as mensagens deste grupo.',
    confirmLabel: 'Sair',
    successMsg: 'Você saiu do grupo.',
    errorMsg: 'Falha ao sair do grupo.',
    run: async () => {
      await store.dispatch('internalChatRooms/leaveRoom', {
        roomId: props.room.id,
        membershipId: currentMembership.value.id,
      });
      emit('close');
      router.push({
        name: 'internal_chat_home',
        params: { accountId: route.params.accountId },
      });
    },
  };
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
      <GroupSettingsHeader
        :view="view"
        :title="headerTitle"
        @close="emit('close')"
        @back="view = 'main'"
      />

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
        <GroupHeroSection
          :room="room"
          :can-manage="canManage"
          :is-uploading-avatar="isUploadingAvatar"
          :is-editing-name="editingField === 'name'"
          :edit-name="editName"
          :is-saving="isSaving"
          @update:edit-name="editName = $event"
          @avatar-pick="onAvatarPick"
          @remove-avatar="removeAvatar"
          @start-edit-name="startEdit('name')"
          @save-name="saveEdit"
          @cancel-edit-name="cancelEdit"
        />

        <GroupDescriptionSection
          :room="room"
          :can-manage="canManage"
          :is-editing-description="editingField === 'description'"
          :edit-description="editDescription"
          :is-saving="isSaving"
          @update:edit-description="editDescription = $event"
          @start-edit-description="startEdit('description')"
          @save-description="saveEdit"
          @cancel-edit-description="cancelEdit"
        />

        <GroupQuickLinks
          @open-files="view = 'files'"
          @open-favorites="view = 'favorites'"
        />

        <GroupMembersSection
          :room="room"
          :can-manage="canManage"
          :current-user-id="currentUserId"
          :has-bea="hasBea"
          :show-add-member="showAddMember"
          :search="search"
          :candidates="candidates"
          @update:search="search = $event"
          @toggle-add-member="showAddMember = !showAddMember"
          @add-bea="addBea"
          @add-member="addMember"
          @promote="promote"
          @remove-member="removeMember"
        />

        <GroupDangerZone
          :current-membership="currentMembership"
          :is-owner="isOwner"
          :is-deleting-group="isDeletingGroup"
          @leave="leave"
          @delete-group="deleteGroup"
        />
      </div>
    </aside>

    <!-- Confirmação genérica das ações destrutivas (remover membro/imagem,
         sair, excluir grupo) — substitui os confirm()/alert() nativos. -->
    <ConfirmDangerModal
      :show="confirmDialog !== null"
      :title="confirmDialog?.title || ''"
      :message="confirmDialog?.message || ''"
      :confirm-label="confirmDialog?.confirmLabel || 'Confirmar'"
      cancel-label="Cancelar"
      :loading="confirmBusy"
      @confirm="runConfirm"
      @cancel="closeConfirm"
    />
  </div>
</template>
