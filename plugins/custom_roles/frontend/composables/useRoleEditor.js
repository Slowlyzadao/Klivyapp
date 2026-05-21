import { ref, computed } from 'vue';
import klivyRolesApi from '../api/klivyRolesApi.js';
import {
  MODULES,
  emptyPermissionsHash,
  normalizePermissions,
  countActivePermissions,
  flattenPermissions,
  groupPermissions,
} from '../shared/modules.js';
import { presetById } from '../shared/presets.js';

/**
 * Estado e operações do editor de uma Role (criar ou editar).
 */
export function useRoleEditor() {
  const id = ref(null);
  const name = ref('');
  const description = ref('');
  const presetKey = ref(null);
  const permissions = ref(emptyPermissionsHash());
  const isSaving = ref(false);
  const isLoading = ref(false);

  const totalActive = computed(() => countActivePermissions(permissions.value));

  const loadFromRole = role => {
    id.value = role.id ?? null;
    name.value = role.name ?? '';
    description.value = role.description ?? '';
    presetKey.value = role.preset_key ?? null;
    permissions.value = normalizePermissions(role.permissions ?? {});
  };

  const fetch = async roleId => {
    isLoading.value = true;
    try {
      const { data } = await klivyRolesApi.show(roleId);
      loadFromRole(data);
    } finally {
      isLoading.value = false;
    }
  };

  const reset = () => {
    id.value = null;
    name.value = '';
    description.value = '';
    presetKey.value = null;
    permissions.value = emptyPermissionsHash();
  };

  const applyPreset = preset => {
    const p = typeof preset === 'string' ? presetById(preset) : preset;
    if (!p) return;
    presetKey.value = p.id;
    permissions.value = normalizePermissions(p.permissions);
    if (!name.value) name.value = p.label;
    if (!description.value) description.value = p.description;
  };

  const togglePermission = (moduleKey, permKey) => {
    const current = permissions.value[moduleKey]?.[permKey] === true;
    permissions.value = {
      ...permissions.value,
      [moduleKey]: { ...permissions.value[moduleKey], [permKey]: !current },
    };
  };

  const setModuleEnabled = (moduleKey, enabled) => {
    const mod = MODULES.find(m => m.key === moduleKey);
    if (!mod) return;
    const flat = flattenPermissions(mod);
    const current = permissions.value[moduleKey] || {};
    const next = flat.reduce((acc, p) => {
      acc[p.key] = enabled;
      return acc;
    }, { ...current });
    permissions.value = { ...permissions.value, [moduleKey]: next };
  };

  const setGroupEnabled = (moduleKey, groupKey, enabled) => {
    const mod = MODULES.find(m => m.key === moduleKey);
    if (!mod) return;
    const groupPerms = groupPermissions(mod, groupKey);
    if (!groupPerms.length) return;
    const current = permissions.value[moduleKey] || {};
    const next = groupPerms.reduce(
      (acc, p) => {
        acc[p.key] = enabled;
        return acc;
      },
      { ...current }
    );
    permissions.value = { ...permissions.value, [moduleKey]: next };
  };

  const save = async () => {
    isSaving.value = true;
    try {
      const payload = {
        name: name.value.trim(),
        description: description.value.trim(),
        preset_key: presetKey.value,
        permissions: permissions.value,
      };
      const { data } = id.value
        ? await klivyRolesApi.update(id.value, payload)
        : await klivyRolesApi.create(payload);
      loadFromRole(data);
      return data;
    } finally {
      isSaving.value = false;
    }
  };

  return {
    id,
    name,
    description,
    presetKey,
    permissions,
    isSaving,
    isLoading,
    totalActive,
    loadFromRole,
    fetch,
    reset,
    applyPreset,
    togglePermission,
    setModuleEnabled,
    setGroupEnabled,
    save,
  };
}
