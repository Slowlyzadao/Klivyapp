/**
 * useClinicProfile — perfil institucional da clínica (especialidades).
 *
 * Cache em módulo (singleton) pra evitar refetch toda vez que um componente
 * monta — é um perfil que muda raramente. `ensureLoaded()` é idempotente.
 *
 * ⚠️ MULTI-TENANT: o cache é invalidado automaticamente quando `accountId`
 * muda. Hoje o `SidebarAccountSwitcher` já faz `window.location.href` ao
 * trocar conta (full reload zera o módulo), mas keyamos defensivamente —
 * vazamento cross-tenant é bug caro de pegar em review e crítico em prod.
 * Ver AGENTS.md → "Multi-tenancy".
 *
 *   const { profile, ensureLoaded, refresh, save } = useClinicProfile();
 *
 *   profile.value = { default_specialty, enabled_specialties }
 */

import { ref, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import ClinicProfileAPI from '@plugins/beclinic_core/frontend/api/clinicProfile';

const profile = ref({ default_specialty: null, enabled_specialties: [] });
const isLoaded = ref(false);
const isSaving = ref(false);
let cachedAccountId = null;
let inflight = null;

const resetCache = () => {
  profile.value = { default_specialty: null, enabled_specialties: [] };
  isLoaded.value = false;
  inflight = null;
};

// Invalida o cache se o accountId que está sendo consultado é diferente
// do último carregado. Chamado no entry point de cada operação E pelo
// watch dentro do composable, pra cobrir tanto o caso "componente monta
// já em outra conta" quanto "accountId muda durante a vida do componente".
const invalidateIfAccountChanged = currentAccountId => {
  if (cachedAccountId !== currentAccountId) {
    resetCache();
    cachedAccountId = currentAccountId;
  }
};

const fetchProfile = async () => {
  const res = await ClinicProfileAPI.get();
  profile.value = {
    default_specialty: res.data?.default_specialty || null,
    enabled_specialties: Array.isArray(res.data?.enabled_specialties)
      ? res.data.enabled_specialties
      : [],
  };
  isLoaded.value = true;
  return profile.value;
};

export function useClinicProfile() {
  const { accountId } = useAccount();

  // Sincroniza no setup (1ª chamada).
  invalidateIfAccountChanged(accountId.value);

  // Reage a mudanças subsequentes (ex.: componente vivo durante uma navegação
  // entre contas no futuro caso o switcher deixe de fazer reload).
  watch(accountId, newId => invalidateIfAccountChanged(newId));

  const ensureLoaded = () => {
    invalidateIfAccountChanged(accountId.value);
    if (isLoaded.value) return Promise.resolve(profile.value);
    if (inflight) return inflight;
    inflight = fetchProfile().finally(() => {
      inflight = null;
    });
    return inflight;
  };

  const refresh = () => {
    resetCache();
    return ensureLoaded();
  };

  const save = async ({ default_specialty, enabled_specialties }) => {
    isSaving.value = true;
    try {
      const res = await ClinicProfileAPI.update({
        default_specialty,
        enabled_specialties,
      });
      profile.value = {
        default_specialty: res.data?.default_specialty || null,
        enabled_specialties: Array.isArray(res.data?.enabled_specialties)
          ? res.data.enabled_specialties
          : [],
      };
      isLoaded.value = true;
      cachedAccountId = accountId.value;
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[ClinicProfile] Falha ao salvar', error);
      return { ok: false, error };
    } finally {
      isSaving.value = false;
    }
  };

  return { profile, isLoaded, isSaving, ensureLoaded, refresh, save };
}
