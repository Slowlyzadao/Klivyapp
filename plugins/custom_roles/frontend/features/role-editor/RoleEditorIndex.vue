<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';

import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';

import { useRoleEditor } from '../../composables/useRoleEditor.js';
import { MODULES } from '../../shared/modules.js';

import RoleEditorHeader from './components/RoleEditorHeader.vue';
import RoleIdentityForm from './components/RoleIdentityForm.vue';
import ModeTabs from './components/ModeTabs.vue';
import PresetPicker from './components/PresetPicker.vue';
import ModuleSection from './components/ModuleSection.vue';

const route = useRoute();
const router = useRouter();

const editor = useRoleEditor();
const mode = ref('preset');
const expandedModules = ref(new Set());
const isLoadingPage = ref(false);

const accountId = computed(() => route.params.accountId);
const roleId = computed(() => route.params.roleId);
const isEditing = computed(() => !!roleId.value);

const canSave = computed(
  () => editor.name.value.trim().length > 0 && editor.totalActive.value > 0
);

const toggleExpanded = key => {
  const next = new Set(expandedModules.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  expandedModules.value = next;
};

const handleSelectPreset = id => {
  editor.applyPreset(id);
  mode.value = 'custom';
};

const handleSave = async (silent = false) => {
  try {
    await editor.save();
    if (!silent) useAlert('Função salva com sucesso!');
    // Permanece na página de edição depois de salvar.
  } catch (e) {
    const msg = e?.response?.data?.message || 'Erro ao salvar função.';
    useAlert(msg);
  }
};

// Auto-save debounced: dispara 400ms após a última toggle. Só roda no modo
// de edição (já existe roleId) — em criação ainda usa o botão manual porque
// precisa do nome preenchido.
let autoSaveTimer = null;
const scheduleAutoSave = () => {
  if (!isEditing.value) return;
  if (autoSaveTimer) clearTimeout(autoSaveTimer);
  autoSaveTimer = setTimeout(() => {
    if (editor.name.value.trim().length === 0) return;
    handleSave(true);
  }, 400);
};

const handleTogglePermission = (moduleKey, permKey) => {
  editor.togglePermission(moduleKey, permKey);
  scheduleAutoSave();
};

const handleSetModuleEnabled = (moduleKey, enabled) => {
  editor.setModuleEnabled(moduleKey, enabled);
  scheduleAutoSave();
};

const handleSetGroupEnabled = (moduleKey, groupKey, enabled) => {
  editor.setGroupEnabled(moduleKey, groupKey, enabled);
  scheduleAutoSave();
};

const handleBack = () => {
  router.push({
    name: 'klivy_roles_list',
    params: { accountId: accountId.value },
  });
};

onMounted(async () => {
  if (roleId.value) {
    isLoadingPage.value = true;
    try {
      await editor.fetch(roleId.value);
      mode.value = 'custom';
      expandedModules.value = new Set([MODULES[0].key]);
    } catch {
      useAlert('Não foi possível carregar a função.');
      handleBack();
    } finally {
      isLoadingPage.value = false;
    }
  } else {
    expandedModules.value = new Set([MODULES[0].key]);
  }
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoadingPage"
    loading-message="Carregando função…"
  >
    <template #header>
      <RoleEditorHeader
        :is-editing="isEditing"
        :total-active="editor.totalActive.value"
        :is-saving="editor.isSaving.value"
        :can-save="canSave"
        @back="handleBack"
        @save="() => handleSave(false)"
      />
    </template>

    <template #body>
      <div class="flex flex-col gap-6 pb-12">
        <RoleIdentityForm
          :name="editor.name.value"
          :description="editor.description.value"
          @update:name="editor.name.value = $event"
          @update:description="editor.description.value = $event"
        />

        <ModeTabs v-model:mode="mode" />

        <PresetPicker
          v-if="mode === 'preset'"
          :selected-preset-id="editor.presetKey.value"
          @select="handleSelectPreset"
        />

        <div v-else class="space-y-3">
          <p
            class="text-xs text-n-slate-11 px-3 py-2 rounded-md border border-dashed border-n-slate-5 bg-n-slate-2"
          >
            Cada módulo desligado some do menu lateral do usuário. Você pode
            também desligar permissões individuais dentro de um módulo.
          </p>

          <ModuleSection
            v-for="mod in MODULES"
            :key="mod.key"
            :module="mod"
            :permissions="editor.permissions.value"
            :expanded="expandedModules.has(mod.key)"
            @toggle-expanded="toggleExpanded"
            @toggle-permission="handleTogglePermission"
            @toggle-module="handleSetModuleEnabled"
            @toggle-group="handleSetGroupEnabled"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
