<script setup>
/**
 * LockedTab — Componente de fallback para quando o usuário não tem permissão
 * para acessar uma tab/seção protegida pelo PermissionGate.
 *
 * Uso:
 *   <PermissionGate module="patients" action="view_audit" :show-locked="true">
 *     <AuditTab />
 *     <template #locked>
 *       <LockedTab message="Você não tem permissão para acessar a auditoria" />
 *     </template>
 *   </PermissionGate>
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  message: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    default: 'i-lucide-lock',
  },
});

const { t } = useI18n();

const displayMessage = computed(() => {
  return (
    props.message ||
    t(
      'RBAC.LOCKED_TAB_MESSAGE',
      'Você não tem permissão para acessar este conteúdo'
    )
  );
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-4 p-12 text-center min-h-[200px]"
  >
    <div
      class="flex items-center justify-center size-16 rounded-2xl bg-n-alpha-2"
    >
      <i :class="icon" class="size-8 text-n-slate-11" />
    </div>
    <div class="flex flex-col gap-1">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('RBAC.ACCESS_RESTRICTED', 'Acesso restrito') }}
      </h3>
      <p class="text-sm text-n-slate-11 max-w-md">
        {{ displayMessage }}
      </p>
    </div>
  </div>
</template>
