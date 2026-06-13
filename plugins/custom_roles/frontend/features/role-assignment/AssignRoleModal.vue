<script setup>
import { computed, onMounted, ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

import klivyRolesApi from '../../api/klivyRolesApi.js';
import { countActivePermissions } from '../../shared/modules.js';

import RoleOption from './RoleOption.vue';

const props = defineProps({
  user: { type: Object, required: true },
});

const emit = defineEmits(['close', 'assigned']);

const roles = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const selectedRoleId = ref(props.user.klivy_role_id ?? null);

// Ordena por nº de permissões ativas desc (papéis com mais poder no topo);
// empate cai pra ordem alfabética. Mesma regra da lista de Funções.
const sortedRoles = computed(() =>
  [...roles.value].sort((a, b) => {
    const diff =
      countActivePermissions(b.permissions || {}) -
      countActivePermissions(a.permissions || {});
    return diff !== 0 ? diff : a.name.localeCompare(b.name, 'pt-BR');
  })
);

const close = () => emit('close');

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await klivyRolesApi.list();
    roles.value = data;
  } catch {
    useAlert('Erro ao carregar funções.');
  } finally {
    isLoading.value = false;
  }
};

const handleSave = async () => {
  if (!selectedRoleId.value) return;
  isSaving.value = true;
  try {
    await klivyRolesApi.assignToUser(selectedRoleId.value, props.user.id);
    const role = roles.value.find(r => r.id === selectedRoleId.value);
    useAlert(`Função "${role?.name}" atribuída a ${props.user.name}.`);
    emit('assigned', role);
  } catch {
    useAlert('Erro ao atribuir função.');
  } finally {
    isSaving.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      header-title="Atribuir função"
      :header-content="`Selecione uma função para ${user.name}.`"
    />

    <div class="flex flex-col w-full px-8 pt-4 pb-2">
      <p
        v-if="isLoading"
        class="text-sm text-n-slate-11 text-center py-8"
      >
        Carregando funções…
      </p>

      <div
        v-else-if="!roles.length"
        class="text-center py-10 px-4 rounded-xl bg-n-slate-2 border border-dashed border-n-slate-5"
      >
        <p class="text-sm text-n-slate-12 font-medium">
          Você ainda não criou nenhuma função.
        </p>
        <p class="text-xs text-n-slate-11 mt-1">
          Acesse Configurações → Funções para criar a primeira.
        </p>
      </div>

      <div v-else class="flex flex-col gap-2 max-h-[50vh] overflow-y-auto">
        <RoleOption
          v-for="role in sortedRoles"
          :key="role.id"
          :role="role"
          :selected="selectedRoleId === role.id"
          :total-permissions="countActivePermissions(role.permissions || {})"
          @select="selectedRoleId = role.id"
        />
      </div>
    </div>

    <div class="flex flex-row justify-end w-full gap-2 px-8 pt-2 pb-6">
      <Button faded slate label="Cancelar" @click="close" />
      <Button
        label="Atribuir função"
        icon="i-lucide-shield-check"
        :is-loading="isSaving"
        :disabled="!selectedRoleId"
        @click="handleSave"
      />
    </div>
  </div>
</template>
