import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useStoreGetters } from 'dashboard/composables/store';

/**
 * Composable principal para verificação de permissões RBAC do BeClinic.
 *
 * Uso:
 *   const { can, scope, isAdmin } = usePermissions();
 *
 *   can('patients', 'view')          // true | false
 *   can('financial', 'view_cashflow') // true | false
 *   scope('agenda')                  // 'all' | 'own'
 *
 * O `can()` retorna true para admins nativos do Chatwoot (isAdmin),
 * garantindo bypass total. Demais usuários consultam a KlivyRole atribuída.
 */
export function usePermissions() {
  const store = useStore();
  const getters = useStoreGetters();

  // Native Chatwoot admin role — bypass total
  const isAdmin = computed(
    () => getters.getCurrentRole.value === 'administrator'
  );

  const permissions = computed(
    () => store.getters['beclinicPermissions/getPermissions']
  );

  const isLoaded = computed(
    () => store.getters['beclinicPermissions/isLoaded']
  );

  /**
   * Check if current user can perform action on module.
   * Admins always return true.
   * @param {string} moduleName - e.g. 'patients', 'agenda', 'financial'
   * @param {string} action - e.g. 'view', 'create', 'delete'
   * @returns {boolean}
   */
  const can = (moduleName, action) => {
    if (isAdmin.value) return true;
    return store.getters['beclinicPermissions/can'](moduleName, action);
  };

  /**
   * Get the scope for a module.
   * Admins always get 'all'.
   * @param {string} moduleName - e.g. 'patients', 'agenda'
   * @returns {'all' | 'own'}
   */
  const scope = moduleName => {
    if (isAdmin.value) return 'all';
    return store.getters['beclinicPermissions/scope'](moduleName);
  };

  /**
   * Returns true if the given module has at least one sub-permission active.
   * Admins always pass. If the module is not present in the hash,
   * fail-open so unmapped modules stay visible.
   * @param {string} moduleName
   * @returns {boolean}
   */
  const moduleEnabled = moduleName => {
    if (isAdmin.value) return true;
    const all = permissions.value || {};
    const mod = all[moduleName];
    if (!mod) return true;
    return Object.entries(mod).some(
      ([key, value]) => key !== 'scope' && value === true
    );
  };

  /**
   * Fetch permissions from the server.
   * Call this once after authentication.
   */
  const fetchPermissions = () => store.dispatch('beclinicPermissions/fetch');

  /**
   * Clear permissions (on logout).
   */
  const clearPermissions = () => store.dispatch('beclinicPermissions/clear');

  return {
    permissions,
    isLoaded,
    isAdmin,
    can,
    scope,
    moduleEnabled,
    fetchPermissions,
    clearPermissions,
  };
}
