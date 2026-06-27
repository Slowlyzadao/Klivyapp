<script setup>
// FE-16/17 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.STICKER_PICKER.*` via i18n. TABS vira `computed` pra
// resolver labels via `t()` (categorias da Klivy). `emptyMessage`
// também usa `t()` por ser dinâmico (depende da aba ativa).
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// FE-8: BeclinicButton no footer do preview. Demais botões (grid de stickers,
// tabs, ações inline com Tooltip) ficam nativos por terem visual muito custom
// (aspect-square, icon-only com badge, etc) e dependerem de wrapping Tooltip.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import StickerCreatorModal from './StickerCreatorModal.vue';

const emit = defineEmits(['select', 'close']);
const store = useStore();
const { t } = useI18n();

// Tabs: 'recent' | 'all' | 'dentista' | 'bem_estar' | 'estetica' | 'mine'
const TABS = computed(() => [
  { key: 'recent', label: t('INTERNAL_CHAT.STICKER_PICKER.TAB_RECENT'), icon: 'i-lucide-clock' },
  { key: 'all', label: t('INTERNAL_CHAT.STICKER_PICKER.TAB_ALL'), icon: 'i-lucide-star' },
  { key: 'dentista', label: t('INTERNAL_CHAT.STICKER_PICKER.TAB_DENTIST'), icon: 'i-ph-tooth' },
  { key: 'bem_estar', label: t('INTERNAL_CHAT.STICKER_PICKER.TAB_WELLNESS'), icon: 'i-ph-leaf' },
  { key: 'estetica', label: t('INTERNAL_CHAT.STICKER_PICKER.TAB_AESTHETICS'), icon: 'i-ph-sparkle' },
  { key: 'mine', label: t('INTERNAL_CHAT.STICKER_PICKER.TAB_MINE'), icon: 'i-lucide-user' },
]);
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
    return t('INTERNAL_CHAT.STICKER_PICKER.EMPTY_RECENT');
  }
  if (tab.value === 'mine') {
    return t('INTERNAL_CHAT.STICKER_PICKER.EMPTY_MINE');
  }
  if (tab.value === 'all') {
    return t('INTERNAL_CHAT.STICKER_PICKER.EMPTY_ALL');
  }
  const label = TABS.value.find(opt => opt.key === tab.value)?.label;
  return t('INTERNAL_CHAT.STICKER_PICKER.EMPTY_CATEGORY', { label });
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
  <!-- UX-fix 2026-05-20: posicionamento alinhado ao botão de figurinhas
       (canto esquerdo do composer) em vez de centralizado/esticado. Antes
       `left-0 right-0 mx-auto max-w-md` deixava o popover flutuando no
       meio do composer container (que ocupa a largura toda). Agora `left-2`
       ancora à esquerda + width fixa 360px (com fallback mobile via
       `max-w-[calc(100vw-32px)]`). -->
  <div
    class="absolute bottom-full left-2 mb-2 w-[360px] max-w-[calc(100vw-32px)] z-30 rounded-xl shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden ic-sticker-pop"
  >
    <header class="flex items-center justify-between px-3 pt-3 gap-2">
      <div class="flex items-center gap-0.5 overflow-x-auto ic-tabs-scroll flex-1">
        <Tooltip
          v-for="opt in TABS"
          :key="opt.key"
          :label="opt.label"
        >
          <button
            type="button"
            class="inline-flex items-center justify-center w-10 h-10 rounded-lg transition shrink-0"
            :class="
              tab === opt.key
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
            "
            @click="tab = opt.key"
          >
            <span :class="opt.icon" class="text-xl" />
          </button>
        </Tooltip>
      </div>
      <Tooltip :label="$t('INTERNAL_CHAT.STICKER_PICKER.CLOSE_TOOLTIP')">
        <button
          type="button"
          class="inline-flex items-center justify-center w-10 h-10 rounded-lg text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 shrink-0"
          @click="emit('close')"
        >
          <span class="i-lucide-x text-xl" />
        </button>
      </Tooltip>
    </header>

    <p class="px-3 pt-1 text-[10px] font-medium uppercase tracking-wide text-n-slate-11">
      {{ TABS.find(opt => opt.key === tab)?.label }}
    </p>

    <div class="px-3 pt-2">
      <input
        v-model="search"
        type="text"
        :placeholder="$t('INTERNAL_CHAT.STICKER_PICKER.SEARCH_PLACEHOLDER')"
        class="w-full px-3 py-1.5 text-xs rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-1 focus:ring-n-brand"
      >
    </div>

    <div class="max-h-[320px] overflow-y-auto ic-thread-scroll p-2">
      <div v-if="isFetching && !allStickers.length" class="py-8 text-center text-xs text-n-slate-11">
        {{ $t('INTERNAL_CHAT.STICKER_PICKER.LOADING') }}
      </div>

      <!-- UX-fix 2026-05-20: grid de 5→4 colunas + gap maior pra stickers
           maiores e mais clicáveis. Width do popover (360px) acomoda
           4 items de ~75px confortavelmente. -->
      <div v-else class="grid grid-cols-4 gap-2">
        <!-- Botão Criar aparece em 'Salvas' e 'Minhas' (nas categorias da Klivy não faz sentido criar). -->
        <Tooltip
          v-if="tab === 'all' || tab === 'mine'"
          :label="$t('INTERNAL_CHAT.STICKER_PICKER.CREATE_TOOLTIP')"
        >
          <button
            type="button"
            class="aspect-square flex flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-n-weak text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
            @click="showCreator = true"
          >
            <span class="i-lucide-plus text-xl" />
            <span class="text-[10px] font-medium">{{ $t('INTERNAL_CHAT.STICKER_PICKER.CREATE_LABEL') }}</span>
          </button>
        </Tooltip>

        <Tooltip
          v-for="s in visible"
          :key="s.id"
          :label="s.name || $t('INTERNAL_CHAT.STICKER_PICKER.STICKER_FALLBACK_NAME')"
        >
          <button
            type="button"
            class="aspect-square flex items-center justify-center rounded-lg bg-n-alpha-1 hover:bg-n-alpha-2 transition relative group/st"
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
            <!-- UX-fix 2026-05-20: badge "K" removido. Era marca decorativa
                 nos stickers default da Klivy mas poluía visualmente o
                 picker (especialmente em grid 4×N onde cada sticker tem
                 ~75px de altura — o badge ocupava ~10% do thumbnail).
                 A informação "default vs custom" continua acessível via
                 outros sinais (categoria/tab + permissão pra excluir). -->

          </button>
        </Tooltip>

        <p
          v-if="!visible.length && !isFetching"
          class="col-span-4 py-6 text-center text-xs text-n-slate-11"
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
        <Tooltip :label="$t('INTERNAL_CHAT.STICKER_PICKER.BACK_TOOLTIP')">
          <button
            type="button"
            class="inline-flex items-center gap-1 text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
            @click="closePreview"
          >
            <span class="i-lucide-arrow-left text-base" />
            <span>{{ $t('INTERNAL_CHAT.STICKER_PICKER.BACK_LABEL') }}</span>
          </button>
        </Tooltip>
        <Tooltip :label="$t('INTERNAL_CHAT.STICKER_PICKER.CLOSE_TOOLTIP')">
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="emit('close')"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </Tooltip>
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
          <BeclinicButton
            :label="$t('INTERNAL_CHAT.STICKER_PICKER.SEND')"
            icon="i-lucide-send"
            size="sm"
            @click="select(previewSticker); closePreview()"
          />
          <Tooltip
            v-if="!previewSticker.is_default"
            :label="$t('INTERNAL_CHAT.STICKER_PICKER.REMOVE_FAVORITE_TOOLTIP')"
          >
            <button
              type="button"
              class="px-3 py-2 text-sm font-medium rounded-md text-n-amber-11 hover:bg-n-amber-3"
              @click="e => toggleFavorite(previewSticker.id, e)"
            >
              <span class="i-lucide-star-off align-middle text-base" />
            </button>
          </Tooltip>
        </div>
        <p
          v-if="previewSticker.is_default"
          class="text-center text-[10px] text-n-slate-10"
        >
          {{ $t('INTERNAL_CHAT.STICKER_PICKER.DEFAULT_FOOTER_HINT') }}
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
