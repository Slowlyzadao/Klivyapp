<script setup>
// FE-16/17 + ARCH-23 (auditoria 2026-05-19): strings PT-BR migradas pra
// `INTERNAL_CHAT.ATTACHMENT_BUBBLE.*` via i18n. `formatLightboxTime` usa
// `useI18n()` em JS pra montar "Hoje às {time}" / "Ontem às {time}" /
// "{date} às {time}" — formatação numérica (hour/minute, day/month/year)
// segue com API nativa do browser (`toLocaleTimeString`/`toLocaleDateString`).
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import AudioMessage from './AudioMessage.vue';

const props = defineProps({
  attachments: { type: Array, required: true },
  isOwn: { type: Boolean, default: false },
  sender: { type: Object, default: () => ({}) },
  messageCreatedAt: { type: String, default: null },
});

const { t } = useI18n();

const lightbox = ref(null); // { url, name } | null
const videoLightbox = ref(null); // { url, name } | null

const openLightbox = att => {
  lightbox.value = { url: att.file_url, name: att.file_name };
};
const closeLightbox = () => {
  lightbox.value = null;
};
const openVideoLightbox = att => {
  videoLightbox.value = {
    url: att.file_url,
    name: att.file_name,
    downloadUrl: att.download_url || att.file_url,
  };
};
const closeVideoLightbox = () => {
  videoLightbox.value = null;
};

// Fechar overlays com Escape
const onKeydown = e => {
  if (e.key !== 'Escape') return;
  if (videoLightbox.value) closeVideoLightbox();
  else if (lightbox.value) closeLightbox();
};
onMounted(() => document.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));

// Header do lightbox: "Hoje às 13:41" / "Ontem às ..." / "DD/MM/YYYY às ..."
const formatLightboxTime = ts => {
  if (!ts) return '';
  const d = new Date(ts);
  const today = new Date();
  const yest = new Date(today);
  yest.setDate(yest.getDate() - 1);
  const time = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === today.toDateString()) {
    return t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.DATE_TODAY', { time });
  }
  if (d.toDateString() === yest.toDateString()) {
    return t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.DATE_YESTERDAY', { time });
  }
  const date = d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
  return t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.DATE_DEFAULT', { date, time });
};

// thumb_url usa ActiveStorage::Representation, que precisa de ImageMagick.
// Se a representação 500ar (imagem original gigante, libvips ausente, etc),
// caímos pro file_url original como fallback no próprio <img>.
const onImgError = (event, att) => {
  const img = event.target;
  if (img.src !== att.file_url) {
    img.src = att.file_url;
  }
};

// mp4 com só track de áudio (export de gravador, áudio empacotado em MP4)
// chega do backend classificado como `video` porque o mime é `video/mp4`.
// O <video> renderiza com 300x150 default mesmo sem frames — fica um vazio
// gigante. Quando metadata carrega, se videoHeight é 0, troca pro
// AudioMessage. Evita o piscar usando reactive Set.
const audioOnlyVideoIds = ref(new Set());
const onVideoMetadata = (event, attId) => {
  if (event.target.videoHeight === 0) {
    const next = new Set(audioOnlyVideoIds.value);
    next.add(attId);
    audioOnlyVideoIds.value = next;
  }
};
const isAudioOnlyVideo = attId => audioOnlyVideoIds.value.has(attId);

const formatSize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};
</script>

<template>
  <div class="space-y-2">
    <template v-for="att in attachments" :key="att.id">
      <!-- Imagem -->
      <button
        v-if="att.file_type === 'image'"
        type="button"
        class="block max-w-[280px] overflow-hidden rounded-lg cursor-zoom-in"
        @click="openLightbox(att)"
      >
        <img
          :src="att.thumb_url || att.file_url"
          :alt="att.file_name"
          class="object-cover w-full max-h-[300px]"
          loading="lazy"
          @error="onImgError($event, att)"
        >
      </button>

      <!-- mp4 detectado como audio-only via metadata: vira AudioMessage -->
      <AudioMessage
        v-else-if="att.file_type === 'video' && isAudioOnlyVideo(att.id)"
        :src="att.file_url"
        :is-own="isOwn"
        :sender="sender"
      />

      <!-- Vídeo (thumbnail clicável; abre lightbox com controls + autoplay) -->
      <button
        v-else-if="att.file_type === 'video'"
        type="button"
        class="relative block max-w-[320px] rounded-lg overflow-hidden cursor-pointer group/vid"
        @click="openVideoLightbox(att)"
      >
        <video
          :src="att.file_url"
          preload="metadata"
          muted
          class="block w-full max-w-[320px] max-h-[300px]"
          @loadedmetadata="onVideoMetadata($event, att.id)"
        />
        <span
          class="absolute inset-0 flex items-center justify-center bg-black/20 transition group-hover/vid:bg-black/35"
        >
          <span
            class="flex items-center justify-center w-14 h-14 rounded-full bg-black/60 text-white"
          >
            <span class="i-lucide-play text-2xl translate-x-0.5" />
          </span>
        </span>
      </button>

      <!-- Áudio (player WhatsApp-style com waveform) -->
      <AudioMessage
        v-else-if="att.file_type === 'audio'"
        :src="att.file_url"
        :is-own="isOwn"
        :sender="sender"
      />

      <!-- Arquivo genérico -->
      <a
        v-else
        :href="att.download_url || att.file_url"
        :download="att.file_name"
        target="_blank"
        rel="noopener"
        class="flex items-center gap-2 px-3 py-2 rounded-md max-w-[280px] transition"
        :class="
          isOwn
            ? 'ic-file-own'
            : 'bg-n-alpha-1 hover:bg-n-alpha-2 text-n-slate-12'
        "
      >
        <span class="i-lucide-file text-2xl shrink-0" />
        <div class="flex-1 min-w-0">
          <p class="text-xs font-medium truncate">{{ att.file_name }}</p>
          <p
            class="text-[10px]"
            :class="isOwn ? 'ic-file-own-meta' : 'text-n-slate-11'"
          >
            {{ formatSize(att.file_size) }}
          </p>
        </div>
        <span class="i-lucide-download text-base shrink-0" />
      </a>
    </template>

    <!-- Lightbox de imagem -->
    <Teleport to="body">
      <div
        v-if="lightbox"
        class="fixed inset-0 z-[60] flex items-center justify-center p-6 bg-black/85 cursor-zoom-out"
        @click.self="closeLightbox"
      >
        <button
          type="button"
          class="absolute top-4 right-4 inline-flex items-center justify-center w-10 h-10 rounded-full bg-white/10 text-white hover:bg-white/20"
          @click="closeLightbox"
        >
          <span class="i-lucide-x text-xl" />
        </button>
        <img
          :src="lightbox.url"
          :alt="lightbox.name"
          class="max-w-[90vw] max-h-[90vh] rounded-lg shadow-2xl"
        >
      </div>
    </Teleport>

    <!-- Lightbox de vídeo (estilo WhatsApp): backdrop branco sólido cobrindo
         tudo, header com sender + ações em cima, vídeo central com controls
         nativos. Click fora ou Esc fecha. -->
    <Teleport to="body">
      <div
        v-if="videoLightbox"
        class="fixed inset-0 z-[100] flex flex-col"
        style="background-color: #ffffff;"
        @click.self="closeVideoLightbox"
      >
        <header class="flex items-center justify-between px-4 py-3 shrink-0">
          <div class="flex items-center gap-3 min-w-0">
            <Avatar
              :name="sender.name || $t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.USER_FALLBACK_NAME')"
              :src="sender.avatar_url || ''"
              :size="36"
              rounded-full
            />
            <div class="min-w-0">
              <p class="text-sm font-semibold truncate" style="color: #0f172a;">
                {{ sender.name || $t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.USER_FALLBACK_NAME') }}
              </p>
              <p class="text-xs truncate" style="color: rgba(15, 23, 42, 0.65);">
                {{ formatLightboxTime(props.messageCreatedAt) }}
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <Tooltip :label="$t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.DOWNLOAD_TOOLTIP')">
              <a
                :href="videoLightbox.downloadUrl || videoLightbox.url"
                :download="videoLightbox.name"
                target="_blank"
                rel="noopener"
                class="ic-lightbox-btn"
              >
                <span class="i-lucide-download text-xl" />
              </a>
            </Tooltip>
            <Tooltip :label="$t('INTERNAL_CHAT.ATTACHMENT_BUBBLE.CLOSE_TOOLTIP')">
              <button
                type="button"
                class="ic-lightbox-btn"
                @click="closeVideoLightbox"
              >
                <span class="i-lucide-x text-xl" />
              </button>
            </Tooltip>
          </div>
        </header>
        <div
          class="flex-1 flex items-center justify-center px-6 pb-6 min-h-0"
          @click.self="closeVideoLightbox"
        >
          <video
            :src="videoLightbox.url"
            controls
            autoplay
            class="max-w-[90vw] max-h-full rounded-lg shadow-2xl"
          />
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style>
/* Card de arquivo dentro do bubble verde (own). Mesmo tom do reply embed:
   slate escuro translúcido + borda esquerda verde escura = highlight estilo
   WhatsApp, sem perder contraste. */
.ic-file-own {
  background-color: rgba(15, 23, 42, 0.06);
  color: #0f172a;
}
.ic-file-own:hover {
  background-color: rgba(15, 23, 42, 0.10);
}
.ic-file-own-meta {
  color: rgba(15, 23, 42, 0.60);
}
.dark .ic-file-own {
  background-color: rgba(255, 255, 255, 0.08);
  color: #e2e8f0;
}
.dark .ic-file-own:hover {
  background-color: rgba(255, 255, 255, 0.14);
}
.dark .ic-file-own-meta {
  color: rgba(226, 232, 240, 0.65);
}

/* Botões do header do lightbox de vídeo: ícone preto sobre fundo branco. */
.ic-lightbox-btn {
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
.ic-lightbox-btn:hover {
  background-color: rgba(15, 23, 42, 0.12);
}
</style>
