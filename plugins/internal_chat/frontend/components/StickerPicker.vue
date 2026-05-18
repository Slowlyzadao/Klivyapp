<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import StickerCreatorModal from './StickerCreatorModal.vue';

const emit = defineEmits(['select', 'close']);
const store = useStore();

// Tabs: 'recent' | 'all' | 'dentista' | 'bem_estar' | 'estetica' | 'mine'
const TABS = [
  { key: 'recent', label: 'Recentes', icon: 'i-lucide-clock' },
  { key: 'all', label: 'Salvas', icon: 'i-lucide-star' },
  { key: 'dentista', label: 'Dentista', icon: 'i-ph-tooth' },
  { key: 'bem_estar', label: 'Bem-estar', icon: 'i-ph-leaf' },
  { key: 'estetica', label: 'Estética', icon: 'i-ph-sparkle' },
  { key: 'mine', label: 'Minhas', icon: 'i-lucide-user' },
];
const tab = ref('recent');
const showCreator = ref(false);
const search = ref('');
const previewSticker = ref(null);

onMounted(() => {
  // Refresh ao abrir: traz "salvas" e "recentes" em paralelo. Recentes vem
  // do backend já ordenado por frequência DESC.
  store.dispatch('internalChatStickers/refresh').then(() => {
    // Se não tem nenhuma recente (user nunca enviou), pula pra "Salvas".
    if (!recent.value.length) tab.value = 'all';
  });
});

const isFetching = computed(
  () => store.getters['internalChatStickers/getUIFlags'].isFetching
);

const allStickers = computed(() => store.getters['internalChatStickers/getAll']);
const recent = computed(() => store.getters['internalChatStickers/getRecent']);
const mine = computed(() => store.getters['internalChatStickers/getMine']);

const visible = computed(() => {
  let list;
  if (tab.value === 'recent') {
    list = recent.value;
  } else if (tab.value === 'mine') {
    list = mine.value;
  } else if (tab.value === 'all') {
    list = allStickers.value;
  } else {
    // Categoria de defaults da Klivy
    list = allStickers.value.filter(s => s.category === tab.value);
  }
  if (!search.value.trim()) return list;
  const q = search.value.trim().toLowerCase();
  return list.filter(s => (s.name || '').toLowerCase().includes(q));
});

const emptyMessage = computed(() => {
  if (tab.value === 'recent') {
    return 'Suas figurinhas mais usadas aparecem aqui. Envie algumas pra começar.';
  }
  if (tab.value === 'mine') {
    return 'Você ainda não criou figurinhas. Clique em + Criar.';
  }
  if (tab.value === 'all') {
    return 'Nenhuma figurinha salva. Crie uma ou pegue das categorias da Klivy.';
  }
  return `A Klivy ainda não tem figurinhas em ${TABS.find(t => t.key === tab.value)?.label}.`;
});

const select = sticker => emit('select', sticker);

const openPreview = sticker => {
  previewSticker.value = sticker;
};

const closePreview = () => {
  previewSticker.value = null;
};

const toggleFavorite = async (id, e) => {
  e.stopPropagation();
  try {
    await store.dispatch('internalChatStickers/toggleFavorite', id);
    // Após desfavoritar, o sticker pode ter sumido do store (cascade-delete
    // se ninguém mais tinha salvo). Re-lê o getter pra fechar o preview se foi.
    const next = store.getters['internalChatStickers/getById'](id);
    if (previewSticker.value && previewSticker.value.id === id) {
      previewSticker.value = next || null;
      if (!next) closePreview();
    }
  } catch {
    /* noop */
  }
};
</script>

<template>
  <div
    class="absolute bottom-full left-0 right-0 mx-auto mb-2 w-full max-w-md z-30 rounded-xl shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden ic-sticker-pop"
  >
    <header class="flex items-center justify-between px-3 pt-3 gap-2">
      <div class="flex items-center gap-0.5 overflow-x-auto ic-tabs-scroll flex-1">
        <button
          v-for="t in TABS"
          :key="t.key"
          type="button"
          class="inline-flex items-center justify-center w-8 h-8 rounded-md transition shrink-0"
          :class="
            tab === t.key
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
          "
          :title="t.label"
          @click="tab = t.key"
        >
          <span :class="t.icon" class="text-base" />
        </button>
      </div>
      <button
        type="button"
        class="text-n-slate-11 hover:text-n-slate-12 shrink-0"
        title="Fechar"
        @click="emit('close')"
      >
        <span class="i-lucide-x text-base" />
      </button>
    </header>

    <p class="px-3 pt-1 text-[10px] font-medium uppercase tracking-wide text-n-slate-11">
      {{ TABS.find(t => t.key === tab)?.label }}
    </p>

    <div class="px-3 pt-2">
      <input
        v-model="search"
        type="text"
        placeholder="Pesquisar por nome..."
        class="w-full px-3 py-1.5 text-xs rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-1 focus:ring-n-brand"
      >
    </div>

    <div class="max-h-[320px] overflow-y-auto ic-thread-scroll p-2">
      <div v-if="isFetching && !allStickers.length" class="py-8 text-center text-xs text-n-slate-11">
        Carregando…
      </div>

      <div v-else class="grid grid-cols-5 gap-1.5">
        <!-- Botão Criar aparece em 'Salvas' e 'Minhas' (nas categorias da Klivy não faz sentido criar). -->
        <button
          v-if="tab === 'all' || tab === 'mine'"
          type="button"
          class="aspect-square flex flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-n-weak text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
          title="Criar nova figurinha"
          @click="showCreator = true"
        >
          <span class="i-lucide-plus text-xl" />
          <span class="text-[10px] font-medium">Criar</span>
        </button>

        <button
          v-for="s in visible"
          :key="s.id"
          type="button"
          class="aspect-square flex items-center justify-center rounded-lg bg-n-alpha-1 hover:bg-n-alpha-2 transition relative group/st"
          :title="s.name || 'figurinha'"
          @click="select(s)"
          @contextmenu.prevent="openPreview(s)"
        >
          <img
            v-if="s.image_url"
            :src="s.image_url"
            class="object-contain w-full h-full p-0.5"
            loading="lazy"
            draggable="false"
          >
          <span
            v-if="s.is_default"
            class="absolute top-0.5 right-0.5 text-[8px] font-bold uppercase tracking-wide px-1 rounded bg-n-brand text-white"
            title="Figurinha padrão da Klivy"
          >K</span>
        </button>

        <p
          v-if="!visible.length && !isFetching"
          class="col-span-5 py-6 text-center text-xs text-n-slate-11"
        >
          {{ emptyMessage }}
        </p>
      </div>
    </div>

    <StickerCreatorModal
      v-if="showCreator"
      @close="showCreator = false"
      @created="showCreator = false"
    />

    <!-- Preview do sticker: ocupa o picker inteiro (in-place, lado esquerdo,
         logo acima do botão sticker). Imagem ocupa quase todo o quadrado. -->
    <div
      v-if="previewSticker"
      class="absolute inset-0 z-10 bg-n-solid-1 flex flex-col"
    >
      <header class="flex items-center justify-between px-3 pt-3">
        <button
          type="button"
          class="inline-flex items-center gap-1 text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
          title="Voltar"
          @click="closePreview"
        >
          <span class="i-lucide-arrow-left text-base" />
          <span>Voltar</span>
        </button>
        <button
          type="button"
          class="text-n-slate-11 hover:text-n-slate-12"
          title="Fechar"
          @click="emit('close')"
        >
          <span class="i-lucide-x text-base" />
        </button>
      </header>

      <div class="flex-1 flex items-center justify-center p-2 min-h-0">
        <img
          :src="previewSticker.image_url"
          class="object-contain max-w-full max-h-full"
          draggable="false"
        >
      </div>

      <footer class="px-3 pb-3 pt-2 border-t border-n-weak space-y-2">
        <p
          v-if="previewSticker.name"
          class="text-center text-sm font-medium text-n-slate-12"
        >
          {{ previewSticker.name }}
        </p>
        <div class="flex justify-center gap-2">
          <button
            type="button"
            class="px-4 py-2 text-sm font-medium text-white rounded-md bg-n-brand hover:brightness-110"
            @click="select(previewSticker); closePreview()"
          >
            <span class="i-lucide-send align-middle text-base" />
            <span class="ml-1 align-middle">Enviar</span>
          </button>
          <button
            v-if="!previewSticker.is_default"
            type="button"
            class="px-3 py-2 text-sm font-medium rounded-md text-n-amber-11 hover:bg-n-amber-3"
            title="Remover das favoritas"
            @click="e => toggleFavorite(previewSticker.id, e)"
          >
            <span class="i-lucide-star-off align-middle text-base" />
          </button>
        </div>
        <p
          v-if="previewSticker.is_default"
          class="text-center text-[10px] text-n-slate-10"
        >
          Figurinha padrão da Klivy
        </p>
      </footer>
    </div>
  </div>
</template>

<style>
.ic-sticker-pop {
  animation: ic-sticker-pop 0.18s ease-out;
}
@keyframes ic-sticker-pop {
  from { opacity: 0; transform: translateY(8px); }
  to   { opacity: 1; transform: translateY(0); }
}
.ic-tabs-scroll::-webkit-scrollbar {
  height: 0;
}
</style>
