<script setup>
defineProps({
  title: { type: String, default: 'Acesso restrito' },
  message: {
    type: String,
    default:
      'Você não tem permissão para visualizar esta área. Fale com o administrador da conta caso precise de acesso.',
  },
  compact: { type: Boolean, default: false },
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center text-center w-full"
    :class="compact ? 'py-10 gap-3' : 'py-20 gap-4'"
  >
    <div
      class="flex items-center justify-center rounded-full bg-n-slate-3 text-n-slate-11"
      :class="compact ? 'w-12 h-12' : 'w-16 h-16'"
    >
      <i class="i-lucide-lock" :class="compact ? 'w-5 h-5' : 'w-7 h-7'" />
    </div>
    <div class="flex flex-col gap-1 max-w-md px-4">
      <h3 class="text-heading-3 text-n-slate-12">{{ title }}</h3>
      <p class="text-body-main text-n-slate-11">{{ message }}</p>
    </div>
  </div>
</template>
