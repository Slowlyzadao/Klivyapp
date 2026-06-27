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

  router.beforeEach((to, _from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    userAuthentication.then(() => {
      // RBAC navigation guard: check meta.rbac on routes
      if (to.meta?.rbac && store.getters.isLoggedIn) {
        const { module: mod, action } = to.meta.rbac;
        const chatwootRole = store.getters.getCurrentRole;
        const permissions = store.getters['beclinicPermissions/getPermissions'];

        // Chatwoot administrators bypass all checks
        const isBypass = chatwootRole === 'administrator';

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
