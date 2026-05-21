<script setup>
/**
 * Page403 — Página de acesso negado (403 Forbidden).
 *
 * Exibida quando um navigation guard detecta que o usuário não tem
 * permissão para acessar uma rota protegida.
 *
 * Uso no router:
 *   { path: '/403', name: 'page403', component: Page403 }
 */
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

const { t } = useI18n();
const router = useRouter();

const goBack = () => {
  if (window.history.length > 1) {
    router.back();
  } else {
    router.push('/');
  }
};
</script>

<template>
  <div
    class="flex flex-col items-center justify-center w-full h-full gap-6 bg-n-background p-8"
  >
    <div
      class="flex items-center justify-center size-24 rounded-3xl bg-n-alpha-2"
    >
      <i class="i-lucide-shield-x size-12 text-r-400" />
    </div>

    <div class="flex flex-col items-center gap-2 text-center max-w-lg">
      <h1 class="text-2xl font-semibold text-n-slate-12">
        {{ t('RBAC.PAGE_403_TITLE', 'Acesso negado') }}
      </h1>
      <p class="text-base text-n-slate-11">
        {{
          t(
            'RBAC.PAGE_403_MESSAGE',
            'Você não tem permissão para acessar esta página. Fale com o administrador da sua conta se precisar de acesso.'
          )
        }}
      </p>
    </div>

    <button
      class="inline-flex items-center gap-2 px-5 py-2.5 text-sm font-medium rounded-xl bg-n-brand text-white hover:opacity-90 transition-opacity"
      @click="goBack"
    >
      <i class="i-lucide-arrow-left size-4" />
      {{ t('RBAC.GO_BACK', 'Voltar') }}
    </button>
  </div>
</template>
