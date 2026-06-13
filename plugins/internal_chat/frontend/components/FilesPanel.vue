<script setup>
// FE-16/17 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.FILES.*` via i18n. `useI18n()` em JS pra resolver
// `error` (catch) e helper `formatDate` (Hoje/Ontem/data).
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// FE-8: BeclinicButton para botão de retry (mantém ações de tabs/grid nativas
// por terem layout custom — sub-tabs com border-b e cards com aspect-square).
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import AttachmentsAPI from '@plugins/internal_chat/frontend/api/attachments';

const props = defineProps({
  roomId: { type: Number, required: true },
});

const { t } = useI18n();

const subTab = ref('media'); // 'media' | 'documents'
const items = ref([]);
const loading = ref(false);
const error = ref('');
const selected = ref(null); // attachment selecionado pra abrir no lightbox

const fetchItems = async () => {
  loading.value = true;
  error.value = '';
  try {
    const res = await AttachmentsAPI.list(props.roomId, { type: subTab.value });
    items.value = res.data?.data || [];
  } catch {
    error.value = t('INTERNAL_CHAT.FILES.ERROR_LOAD');
  } finally {
    loading.value = false;
  }
};

onMounted(fetchItems);
watch(subTab, fetchItems);

const openItem = item => {
  selected.value = item;
};
const closeItem = () => {
  selected.value = null;
};

const onKeydown = e => {
  if (e.key === 'Escape' && selected.value) closeItem();
};
onMounted(() => document.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));

const formatSize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

const formatDate = ts => {
  if (!ts) return '';
  const d = new Date(ts);
  const today = new Date();
  const yest = new Date(today);
  yest.setDate(yest.getDate() - 1);
  const time = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === today.toDateString()) {
    return t('INTERNAL_CHAT.FILES.DATE_TODAY', { time });
  }
  if (d.toDateString() === yest.toDateString()) {
    return t('INTERNAL_CHAT.FILES.DATE_YESTERDAY', { time });
  }
  const date = d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
  return t('INTERNAL_CHAT.FILES.DATE_DEFAULT', { date, time });
};

const isEmpty = computed(() => !loading.value && items.value.length === 0);

// Ícone do documento por content-type — fallback genérico se não bater.
const docIcon = ct => {
  if (!ct) return 'i-lucide-file';
  if (ct.includes('pdf')) return 'i-lucide-file-text';
  if (ct.includes('sheet') || ct.includes('excel')) return 'i-lucide-file-spreadsheet';
  if (ct.includes('word') || ct.includes('document')) return 'i-lucide-file-text';
  if (ct.includes('zip') || ct.includes('rar') || ct.includes('tar') || ct.includes('7z')) return 'i-lucide-file-archive';
  return 'i-lucide-file';
};
</script>

<template>
  <div class="flex flex-col flex-1 overflow-hidden">
    <!-- Sub-tabs: Imagens e vídeos / Documentos -->
    <div class="flex border-b border-n-weak px-5">
      <button
        type="button"
        class="px-4 py-2 text-sm font-medium transition border-b-2"
        :class="
          subTab === 'media'
            ? 'text-n-brand border-n-brand'
            : 'text-n-slate-11 border-transparent hover:text-n-slate-12'
        "
        @click="subTab = 'media'"
      >
        {{ $t('INTERNAL_CHAT.FILES.SUBTAB_MEDIA') }}
      </button>
      <button
        type="button"
        class="px-4 py-2 text-sm font-medium transition border-b-2"
        :class="
          subTab === 'documents'
            ? 'text-n-brand border-n-brand'
            : 'text-n-slate-11 border-transparent hover:text-n-slate-12'
        "
        @click="subTab = 'documents'"
      >
        {{ $t('INTERNAL_CHAT.FILES.SUBTAB_DOCUMENTS') }}
      </button>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center py-8 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-2 animate-spin mr-2 text-base" />
      {{ $t('INTERNAL_CHAT.FILES.LOADING') }}
    </div>

    <div v-else-if="error" class="flex flex-col items-center py-8 text-sm text-n-ruby-11">
      <span class="i-lucide-alert-circle text-2xl mb-1" />
      {{ error }}
      <BeclinicButton
        class="mt-2"
        :label="$t('INTERNAL_CHAT.FILES.RETRY')"
        variant="link"
        size="sm"
        @click="fetchItems"
      />
    </div>

    <div
      v-else-if="isEmpty"
      class="flex flex-col items-center py-12 text-sm text-n-slate-11"
    >
      <span
        :class="subTab === 'media' ? 'i-lucide-image' : 'i-lucide-file'"
        class="text-3xl mb-2 text-n-slate-9"
      />
      <p>
        {{
          subTab === 'media'
            ? $t('INTERNAL_CHAT.FILES.EMPTY_MEDIA')
            : $t('INTERNAL_CHAT.FILES.EMPTY_DOCUMENTS')
        }}
      </p>
    </div>

    <!-- Grid de mídia (3 colunas) -->
    <div
      v-else-if="subTab === 'media'"
      class="grid grid-cols-3 gap-1 p-2 overflow-y-auto"
    >
      <button
        v-for="item in items"
        :key="item.id"
        type="button"
        class="relative aspect-square rounded overflow-hidden bg-n-alpha-1 cursor-pointer group/file"
        @click="openItem(item)"
      >
        <img
          v-if="item.file_type === 'image'"
          :src="item.thumb_url || item.file_url"
          loading="lazy"
          class="w-full h-full object-cover"
          :alt="item.file_name"
        >
        <video
          v-else
          :src="item.file_url"
          preload="metadata"
          muted
          class="w-full h-full object-cover"
        />
        <span
          v-if="item.file_type === 'video'"
          class="absolute inset-0 flex items-center justify-center bg-black/30 group-hover/file:bg-black/45 transition"
        >
          <span
            class="flex items-center justify-center w-9 h-9 rounded-full bg-black/60 text-white"
          >
            <span class="i-lucide-play text-base translate-x-0.5" />
          </span>
        </span>
      </button>
    </div>

    <!-- Lista de documentos -->
    <ul v-else class="flex-1 overflow-y-auto divide-y divide-n-weak">
      <li v-for="item in items" :key="item.id">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-5 py-3 hover:bg-n-alpha-1 cursor-pointer transition text-start"
          @click="openItem(item)"
        >
          <span
            class="shrink-0 inline-flex items-center justify-center w-10 h-10 rounded-lg bg-n-alpha-2"
          >
            <span :class="docIcon(item.content_type)" class="text-lg text-n-slate-11" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium truncate text-n-slate-12">
              {{ item.file_name }}
            </p>
            <p class="text-xs text-n-slate-11 truncate mt-0.5">
              {{ formatSize(item.file_size) }} · {{ item.sender?.name || $t('INTERNAL_CHAT.FILES.USER_FALLBACK_NAME') }} ·
              {{ formatDate(item.message_created_at) }}
            </p>
          </div>
          <Tooltip :label="$t('INTERNAL_CHAT.FILES.DOWNLOAD_TOOLTIP')">
            <a
              :href="item.download_url || item.file_url"
              :download="item.file_name"
              target="_blank"
              rel="noopener"
              class="shrink-0 p-1.5 rounded text-n-slate-11 hover:bg-n-alpha-2"
              @click.stop
            >
              <span class="i-lucide-download text-base" />
            </a>
          </Tooltip>
        </button>
      </li>
    </ul>

    <!-- Lightbox: backdrop branco, header com sender + ações; conteúdo central
         varia por tipo (img / video / iframe pra PDF). Click fora ou Esc fecha. -->
    <Teleport to="body">
      <div
        v-if="selected"
        class="fixed inset-0 z-[100] flex flex-col"
        style="background-color: #ffffff;"
        @click.self="closeItem"
      >
        <header
          class="flex items-center justify-between px-4 py-3 shrink-0 border-b border-n-weak"
        >
          <div class="flex items-center gap-3 min-w-0">
            <Avatar
              :name="selected.sender?.name || $t('INTERNAL_CHAT.FILES.USER_FALLBACK_NAME')"
              :src="selected.sender?.avatar_url || ''"
              :size="36"
              rounded-full
            />
            <div class="min-w-0">
              <p class="text-sm font-semibold truncate text-n-slate-12">
                {{ selected.sender?.name || $t('INTERNAL_CHAT.FILES.USER_FALLBACK_NAME') }}
              </p>
              <p class="text-xs truncate text-n-slate-11">
                {{ formatDate(selected.message_created_at) }}
                <span v-if="selected.file_name"> · {{ selected.file_name }}</span>
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <Tooltip :label="$t('INTERNAL_CHAT.FILES.DOWNLOAD_TOOLTIP')">
              <a
                :href="selected.download_url || selected.file_url"
                :download="selected.file_name"
                target="_blank"
                rel="noopener"
                class="ic-files-lightbox-btn"
              >
                <span class="i-lucide-download text-xl" />
              </a>
            </Tooltip>
            <Tooltip :label="$t('INTERNAL_CHAT.FILES.CLOSE_TOOLTIP')">
              <button
                type="button"
                class="ic-files-lightbox-btn"
                @click="closeItem"
              >
                <span class="i-lucide-x text-xl" />
              </button>
            </Tooltip>
          </div>
        </header>
        <div
          class="flex-1 flex items-center justify-center p-6 min-h-0"
          @click.self="closeItem"
        >
          <img
            v-if="selected.file_type === 'image'"
            :src="selected.file_url"
            :alt="selected.file_name"
            class="max-w-[90vw] max-h-full rounded-lg shadow-2xl object-contain"
          >
          <video
            v-else-if="selected.file_type === 'video'"
            :src="selected.file_url"
            controls
            autoplay
            class="max-w-[90vw] max-h-full rounded-lg shadow-2xl"
          />
          <!-- FE-6: `title` em <iframe> é atributo A11Y obrigatório (nome
               acessível do frame pra leitores de tela), NÃO tooltip visual.
               Não substituir por <Tooltip>. -->
          <iframe
            v-else
            :src="selected.file_url"
            class="w-[90vw] h-full rounded-lg shadow-2xl bg-white border border-n-weak"
            :title="selected.file_name"
          />
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style>
.ic-files-lightbox-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border-radius: 9999px;
  background-color: rgba(15, 23, 42, 0.06);
  color: #0f172a;
  transition: background-color 120ms ease;
}
.ic-files-lightbox-btn:hover {
  background-color: rgba(15, 23, 42, 0.12);
}
</style>
