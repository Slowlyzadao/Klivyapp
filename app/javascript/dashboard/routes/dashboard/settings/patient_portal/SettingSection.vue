<script setup>
// Seção do painel de configurações com título + subtítulo + slot do conteúdo.
// Reusada para Scheduling/Documents/Messaging/etc.
defineProps({
  title:    { type: String, required: true },
  subtitle: { type: String, default: '' },
});
</script>

<template>
  <section class="bg-n-background rounded-lg p-5 border border-n-weak">
    <header class="mb-4">
      <h3 class="text-base font-semibold text-n-slate-12 m-0">{{ title }}</h3>
      <p v-if="subtitle" class="text-xs text-n-slate-11 m-0 mt-1">{{ subtitle }}</p>
    </header>
    <div class="grid gap-3">
      <slot />
    </div>
  </section>
</template>
