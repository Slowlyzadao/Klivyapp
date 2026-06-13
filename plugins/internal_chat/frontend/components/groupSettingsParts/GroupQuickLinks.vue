<script setup>
// FE-2 (auditoria 2026-05-18): extraído de GroupSettingsDrawer.vue (601 LOC).
// Quick-links pra abrir as sub-views Arquivos / Favoritos. Pai escuta
// os emits e troca `view` correspondente.
defineEmits(['open-files', 'open-favorites']);
</script>

<template>
  <section class="border-b border-n-weak py-1">
    <button
      type="button"
      class="flex items-center w-full gap-3 px-5 py-3 text-start hover:bg-n-alpha-1 transition"
      @click="$emit('open-files')"
    >
      <span class="i-lucide-folder text-lg text-n-slate-11" />
      <span class="flex-1 text-sm font-medium text-n-slate-12">{{ $t('INTERNAL_CHAT.GROUP_SETTINGS.QUICK_LINKS.FILES') }}</span>
      <span class="i-lucide-chevron-right text-base text-n-slate-10" />
    </button>
    <button
      type="button"
      class="flex items-center w-full gap-3 px-5 py-3 text-start hover:bg-n-alpha-1 transition"
      @click="$emit('open-favorites')"
    >
      <span class="i-lucide-star text-lg text-n-slate-11" />
      <span class="flex-1 text-sm font-medium text-n-slate-12">{{ $t('INTERNAL_CHAT.GROUP_SETTINGS.QUICK_LINKS.FAVORITES') }}</span>
      <span class="i-lucide-chevron-right text-base text-n-slate-10" />
    </button>
  </section>
</template>
