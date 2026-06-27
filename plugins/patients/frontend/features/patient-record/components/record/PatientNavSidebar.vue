<script setup>
defineProps({
  tabs: { type: Array, required: true },
  activeTab: { type: String, required: true },
  isOpen: { type: Boolean, default: false },
});

const emit = defineEmits(['update:activeTab', 'update:isOpen']);

const selectTab = id => {
  emit('update:activeTab', id);
  emit('update:isOpen', false);
};

const close = () => emit('update:isOpen', false);
const open = () => emit('update:isOpen', true);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <!-- Overlay para Mobile Sidebar -->
  <div
    v-if="isOpen"
    class="fixed inset-0 bg-slate-900/60 backdrop-blur-[2px] z-40 lg:hidden transition-opacity"
    @click="close"
  />

  <!-- Coluna fixa: desktop = navegação vertical (esquerda do conteúdo).
       Mobile = drawer ancorado à DIREITA, sem border-radius e sem borda
       lateral pra ficar flush com o edge da tela. -->
  <div
    class="menu-sidebar bg-n-background border border-n-strong max-lg:!fixed max-lg:!top-0 max-lg:!right-0 max-lg:!bottom-0 max-lg:!h-[100dvh] max-lg:!w-[280px] max-lg:!max-w-[85vw] max-lg:z-50 max-lg:!rounded-none max-lg:!border-l max-lg:!border-r-0 max-lg:!border-y-0 transition-transform duration-300 transform lg:!translate-x-0 overflow-y-auto"
    :class="[
      isOpen ? 'translate-x-0 !shadow-2xl' : 'translate-x-full',
      'flex flex-col',
    ]"
  >
    <!-- Mobile menu title -->
    <div
      class="lg:hidden flex items-center justify-between p-4 mb-2 border-b border-white/10"
    >
      <span class="font-semibold text-slate-200">Prontuário</span>
      <button class="text-slate-400 hover:text-white" @click="close">
        <i class="i-lucide-x w-5 h-5" />
      </button>
    </div>

    <nav class="vertical-tabs-nav">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        class="vertical-tab-btn"
        :class="{ active: activeTab === tab.id }"
        @click="selectTab(tab.id)"
      >
        <i :class="tab.icon" />
        <span>{{ tab.label }}</span>
      </button>
    </nav>
  </div>

  <!-- Toggle Mobile: ancorado à direita, abaixo da barra de ações pra não
       sobrepor os ícones do header. Mesmo ícone do toggle de contatos do
       Chatwoot pra coerência visual. -->
  <button
    class="lg:hidden fixed top-24 right-6 w-11 h-11 bg-n-solid-2 hover:bg-n-alpha-2 border border-n-weak text-n-slate-12 rounded-full flex items-center justify-center z-30 transition-all duration-200 active:scale-95 shadow-sm"
    title="Abrir prontuário"
    @click="open"
  >
    <i class="i-lucide-panel-right-open w-5 h-5" />
  </button>
</template>
