// store/modules/beclinicPermissions/getters.js
export const getters = {
  getPermissions: state => state.permissions,
  isLoaded: state => state.loaded,
  isLoading: state => state.isLoading,

  // Check if user can perform an action on a module
  // Usage: store.getters['beclinicPermissions/can']('patients', 'view')
  can: state => (moduleName, action) => {
    if (!state.loaded || !state.permissions) return false;
    const modulePerms = state.permissions[moduleName];
    if (!modulePerms) return false;
    return modulePerms[action] === true;
  },

  // Returns the scope ('all' or 'own') for a module
  // Usage: store.getters['beclinicPermissions/scope']('patients')
  scope: state => moduleName => {
    if (!state.loaded || !state.permissions) return 'all';
    const modulePerms = state.permissions[moduleName];
    return modulePerms?.scope || 'all';
  },
};
