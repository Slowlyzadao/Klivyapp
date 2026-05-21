<script setup>
/**
 * LockedContent — Componente visual para exibir conteúdo bloqueado por permissão.
 *
 * Exibe um cadeado + mensagem descritiva quando o usuário não tem acesso.
 * Usado como slot #locked dentro de <PermissionGate>.
 *
 * Uso:
 *   <PermissionGate module="financial" action="view_cashflow" show-locked>
 *     <CashflowReport />
 *     <template #locked>
 *       <LockedContent message="Apenas gerentes têm acesso ao relatório de caixa" />
 *     </template>
 *   </PermissionGate>
 */
defineProps({
  message: {
    type: String,
    default: 'Você não tem permissão para acessar este conteúdo.',
  },
  compact: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-2 text-center text-n-slate-11"
    :class="[compact ? 'py-4 px-3' : 'py-10 px-6']"
  >
    <span
      class="i-lucide-lock-keyhole"
      :class="[compact ? 'size-5' : 'size-8']"
    />
    <p class="mb-0" :class="[compact ? 'text-body-small' : 'text-body-main']">
      {{ message }}
    </p>
  </div>
</template>
