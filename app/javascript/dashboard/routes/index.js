import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const routes = [...dashboard.routes];

export const router = createRouter({ history: createWebHistory(), routes });

export const validateAuthenticateRoutePermission = (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  if (to.name === 'no_accounts' || !to.name) {
    return next(frontendURL(`accounts/${accountId}/dashboard`));
  }

  const klivyPermissions = store.getters['beclinicPermissions/getPermissions'];
  const nextRoute = validateLoggedInRoutes(
    to,
    store.getters.getCurrentUser,
    klivyPermissions
  );
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  // Garante que as permissões Klivy estejam carregadas antes do guard rodar.
  // Sem isso, um reload em rotas restritas (BEA, /mentions, /unattended)
  // pega `klivyPermissions = {}` e cai em `/forbidden` mesmo com permissão
  // total. Reusa a mesma promise pra todas as transições da sessão.
  const ensureKlivyPermissions = () => {
    if (!store.getters.isLoggedIn) return Promise.resolve();
    if (store.getters['beclinicPermissions/isLoaded']) return Promise.resolve();
    return store.dispatch('beclinicPermissions/fetch');
  };

  router.beforeEach((to, _from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    userAuthentication.then(() => ensureKlivyPermissions()).then(() => {
      // RBAC navigation guard: check meta.rbac on routes
      if (to.meta?.rbac && store.getters.isLoggedIn) {
        const { module: mod, action } = to.meta.rbac;
        const beclinicRole =
          store.getters['beclinicPermissions/getBeclinicRole'];
        const chatwootRole = store.getters.getCurrentRole;
        const permissions = store.getters['beclinicPermissions/getPermissions'];

        // Super admins (Chatwoot administrator), donos bypass all checks
        const isBypass =
          chatwootRole === 'administrator' || beclinicRole === 'dono';

        if (!isBypass && mod && action) {
          const modulePerms = permissions?.[mod] || {};
          if (!modulePerms[action]) {
            const { accountId: aid } = to.params;
            const acctId = aid || store.getters.getCurrentAccountId;
            return next({
              name: 'page403',
              params: { accountId: acctId },
            });
          }
        }
      }

      return validateAuthenticateRoutePermission(to, next, store);
    });
  });
};

export default router;
