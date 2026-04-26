<script setup>
import { computed, nextTick, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { usePermissions } from 'dashboard/composables/usePermissions';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const router = useRouter();
const { uiSettings } = useUISettings();
const route = useRoute();
const { can } = usePermissions();

const portals = computed(() => store.getters['portals/allPortals']);
const canManagePortals = computed(() => can('help_center', 'manage_portals'));

const isPortalPresent = portalSlug => {
  return !!portals.value.find(portal => portal.slug === portalSlug);
};

const routeToView = (name, params) => {
  router.replace({ name, params, replace: true });
};

const generateRouterParams = () => {
  const {
    last_active_portal_slug: lastActivePortalSlug,
    last_active_locale_code: lastActiveLocaleCode,
  } = uiSettings.value || {};
  if (isPortalPresent(lastActivePortalSlug)) {
    return {
      portalSlug: lastActivePortalSlug,
      locale: lastActiveLocaleCode,
    };
  }

  if (portals.value.length > 0) {
    const { slug: portalSlug, meta: { default_locale: locale } = {} } =
      portals.value[0];
    return { portalSlug, locale };
  }

  return null;
};

const routeToLastActivePortal = () => {
  const params = generateRouterParams();
  const { navigationPath } = route.params;
  const isAValidRoute = [
    'portals_articles_index',
    'portals_categories_index',
    'portals_locales_index',
    'portals_settings_index',
  ].includes(navigationPath);

  const navigateTo = isAValidRoute ? navigationPath : 'portals_articles_index';
  if (params) {
    return routeToView(navigateTo, params);
  }
  // Sem portal criado, só redireciona pra criação se o usuário pode gerenciar
  // portais. Caso contrário fica na index mostrando estado vazio (não força
  // /forbidden quando o usuário só tem manage_articles, por exemplo).
  if (canManagePortals.value) {
    return routeToView('portals_new', {});
  }
  return null;
};

const performRouting = async () => {
  await store.dispatch('portals/index');
  nextTick(() => routeToLastActivePortal());
};

onMounted(() => performRouting());
</script>

<template>
  <div
    class="flex items-center justify-center w-full bg-n-surface-1 text-n-slate-11"
  >
    <div
      v-if="portals.length === 0 && !canManagePortals"
      class="flex flex-col items-center gap-2 text-center px-6"
    >
      <p class="text-base font-medium">Nenhum portal disponível</p>
      <p class="text-sm text-n-slate-10 max-w-md">
        Peça para um administrador criar um portal antes de você poder
        gerenciar artigos ou categorias.
      </p>
    </div>
    <Spinner v-else />
  </div>
</template>
