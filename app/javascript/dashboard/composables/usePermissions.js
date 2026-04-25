import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useStoreGetters } from 'dashboard/composables/store';

/**
 * Composable principal para verificação de permissões RBAC do BeClinic.
 *
 * Uso:
 *   const { can, scope, isDono, isGerente } = usePermissions();
 *
 *   can('patients', 'view')          // true | false
 *   can('financial', 'view_cashflow') // true | false
 *   scope('agenda')                  // 'all' | 'own'
 *
 * O `can()` retorna true para admins nativos do Chatwoot (isAdmin),
 * garantindo que a equipe BeClinic tenha bypass total.
 */
export function usePermissions() {
  const store = useStore();
  const getters = useStoreGetters();

  // Native Chatwoot admin role — BeClinic super admins use this
  const isAdmin = computed(
    () => getters.getCurrentRole.value === 'administrator'
  );

  const permissions = computed(
    () => store.getters['beclinicPermissions/getPermissions']
  );

  const beclinicRole = computed(
    () => store.getters['beclinicPermissions/getBeclinicRole']
  );

  const team = computed(() => store.getters['beclinicPermissions/getTeam']);

  const isLoaded = computed(
    () => store.getters['beclinicPermissions/isLoaded']
  );

  const isDono = computed(
    () => isAdmin.value || store.getters['beclinicPermissions/isDono']
  );

  const isGerente = computed(
    () =>
      isAdmin.value ||
      isDono.value ||
      store.getters['beclinicPermissions/isGerente']
  );

  const isEspecialista = computed(
    () => store.getters['beclinicPermissions/isEspecialista']
  );

  /**
   * Check if current user can perform action on module.
   * Admins and donos always return true.
   * @param {string} moduleName - e.g. 'patients', 'agenda', 'financial'
   * @param {string} action - e.g. 'view', 'create', 'delete'
   * @returns {boolean}
   */
  const can = (moduleName, action) => {
    if (isAdmin.value) return true;
    if (isDono.value) return true;
    return store.getters['beclinicPermissions/can'](moduleName, action);
  };

  /**
   * Get the scope for a module.
   * Admins and donos always get 'all'.
   * @param {string} moduleName - e.g. 'patients', 'agenda'
   * @returns {'all' | 'own'}
   */
  const scope = moduleName => {
    if (isAdmin.value || isDono.value) return 'all';
    return store.getters['beclinicPermissions/scope'](moduleName);
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
    beclinicRole,
    team,
    isLoaded,
    isAdmin,
    isDono,
    isGerente,
    isEspecialista,
    can,
    scope,
    fetchPermissions,
    clearPermissions,
  };
}
