<script setup>
/**
 * PermissionGate — Componente para controle de acesso visual no frontend.
 *
 * Uso básico (oculta completamente se sem permissão):
 *   <PermissionGate module="financial" action="view_cashflow">
 *     <CashflowReport />
 *   </PermissionGate>
 *
 * Com slot #locked (mostra cadeado quando sem permissão):
 *   <PermissionGate module="patients" action="view_audit" :show-locked="true">
 *     <AuditTab />
 *     <template #locked>
 *       <LockedContent message="Apenas gerentes têm acesso à auditoria" />
 *     </template>
 *   </PermissionGate>
 *
 * Para bypass total (ex: seções que admins sempre veem):
 *   <PermissionGate :always-allow="isAdmin">
 *     ...
 *   </PermissionGate>
 */
import { computed } from 'vue';
import { usePermissions } from 'dashboard/composables/usePermissions';

const props = defineProps({
  // The RBAC module name: 'patients', 'agenda', 'financial', 'chat', 'settings'
  module: {
    type: String,
    default: null,
  },
  // The action within the module: 'view', 'create', 'edit', 'delete', etc.
  action: {
    type: String,
    default: null,
  },
  // If true, shows the #locked slot instead of hiding content when denied
  showLocked: {
    type: Boolean,
    default: false,
  },
  // Override to always allow access regardless of permissions
  alwaysAllow: {
    type: Boolean,
    default: false,
  },
});

const { can, isAdmin } = usePermissions();

const hasAccess = computed(() => {
  if (props.alwaysAllow) return true;
  if (isAdmin.value) return true;
  if (!props.module || !props.action) return true;
  return can(props.module, props.action);
});
</script>

<template>
  <slot v-if="hasAccess" />
  <slot v-else-if="showLocked" name="locked" />
</template>
