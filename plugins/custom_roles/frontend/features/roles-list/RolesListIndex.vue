<script setup>
import { computed, onActivated, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { usePermissions } from 'dashboard/composables/usePermissions';

import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import { useRolesList } from '../../composables/useRolesList.js';
import { countActivePermissions } from '../../shared/modules.js';
import { presetById } from '../../shared/presets.js';

const route = useRoute();
const router = useRouter();
const { isAdmin } = useAdmin();
const { can } = usePermissions();

const canCreateRole = computed(
  () => isAdmin.value || can('settings', 'roles_create')
);
const canEditRole = computed(
  () => isAdmin.value || can('settings', 'roles_edit')
);
const canDeleteRole = computed(
  () => isAdmin.value || can('settings', 'roles_delete')
);

const { roles, isLoading, load, remove } = useRolesList();
const accountId = computed(() => route.params.accountId);
const search = ref('');
const pendingDeleteId = ref(null);

const totalFor = role => countActivePermissions(role.permissions || {});

// Ordena por nº de permissões ativas desc (papéis com mais poder no topo);
// empate cai pra ordem alfabética. Filtro de busca aplica depois.
const sorted = computed(() =>
  [...roles.value].sort((a, b) => {
    const diff = totalFor(b) - totalFor(a);
    return diff !== 0 ? diff : a.name.localeCompare(b.name, 'pt-BR');
  })
);

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return sorted.value;
  return sorted.value.filter(
    r =>
      r.name.toLowerCase().includes(q) ||
      (r.description || '').toLowerCase().includes(q)
  );
});

const presetLabel = role => {
  if (!role.preset_key) return null;
  return presetById(role.preset_key)?.label || null;
};

const goCreate = () =>
  router.push({
    name: 'klivy_roles_new',
    params: { accountId: accountId.value },
  });

const goEdit = id =>
  router.push({
    name: 'klivy_roles_edit',
    params: { accountId: accountId.value, roleId: id },
  });

const handleDelete = async id => {
  if (pendingDeleteId.value === id) {
    try {
      await remove(id);
      useAlert('Função excluída.');
      pendingDeleteId.value = null;
    } catch {
      useAlert('Erro ao excluir função.');
    }
  } else {
    pendingDeleteId.value = id;
    setTimeout(() => {
      if (pendingDeleteId.value === id) pendingDeleteId.value = null;
    }, 4000);
  }
};

onMounted(load);
onActivated(load);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    loading-message="Carregando funções…"
    :no-records-found="!isLoading && roles.length === 0"
    no-records-message="Nenhuma função criada ainda. Clique em Nova função para começar."
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="search"
        title="Funções"
        description="Crie funções com permissões granulares e atribua a cada usuário. Módulos desligados somem do menu lateral automaticamente."
        search-placeholder="Buscar funções…"
        feature-name="custom-roles"
      >
        <template v-if="roles.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ roles.length }} funções
          </span>
        </template>
        <template #actions>
          <Button
            v-if="canCreateRole"
            label="Nova função"
            icon="i-lucide-plus"
            size="sm"
            @click="goCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div v-if="filtered.length === 0 && search" class="py-16 text-center">
        <p class="text-body-main text-n-slate-11">
          Nenhuma função encontrada para "{{ search }}".
        </p>
      </div>

      <div
        v-else
        class="divide-y divide-n-weak border-t border-n-weak mt-4"
      >
        <div
          v-for="role in filtered"
          :key="role.id"
          class="flex items-center justify-between gap-4 py-4"
        >
          <button
            class="flex flex-1 flex-col items-start gap-1 text-left min-w-0"
            :class="{ 'cursor-default': !canEditRole }"
            :disabled="!canEditRole"
            @click="canEditRole && goEdit(role.id)"
          >
            <span class="text-heading-3 text-n-slate-12 truncate">
              {{ role.name }}
            </span>
            <span
              v-if="role.description"
              class="text-body-small text-n-slate-11 truncate w-full"
            >
              {{ role.description }}
            </span>
            <div class="flex items-center gap-2 mt-1 flex-wrap">
              <span
                v-if="presetLabel(role)"
                class="px-2 py-0.5 rounded-md bg-woot-500/10 text-[11px] font-medium text-woot-500"
              >
                {{ presetLabel(role) }}
              </span>
              <span
                class="px-2 py-0.5 rounded-md bg-n-slate-3 text-[11px] font-medium text-n-slate-11"
              >
                {{ totalFor(role) }} permissões
              </span>
              <span
                class="px-2 py-0.5 rounded-md bg-n-slate-3 text-[11px] font-medium text-n-slate-11"
              >
                {{ role.member_count || 0 }} membros
              </span>
            </div>
          </button>

          <div class="flex items-center gap-2 shrink-0">
            <Button
              v-if="canEditRole"
              v-tooltip.top="'Editar função'"
              icon="i-lucide-pencil"
              slate
              sm
              @click="goEdit(role.id)"
            />
            <Button
              v-if="canDeleteRole"
              v-tooltip.top="
                pendingDeleteId === role.id
                  ? 'Clique de novo para confirmar'
                  : 'Excluir função'
              "
              :icon="
                pendingDeleteId === role.id
                  ? 'i-lucide-alert-triangle'
                  : 'i-lucide-trash-2'
              "
              slate
              sm
              :class="
                pendingDeleteId === role.id
                  ? '!text-n-ruby-11 !bg-n-ruby-2'
                  : 'hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2'
              "
              @click="handleDelete(role.id)"
            />
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
