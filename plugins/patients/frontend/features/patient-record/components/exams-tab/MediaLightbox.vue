<script setup>
import { useI18n } from 'vue-i18n';
import {
  isPdf,
  isVideo,
} from '@plugins/patients/frontend/features/patient-record/utils/examClassifiers';

defineProps({
  media: { type: Object, default: null },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const actionBtn = [
  'h-9 w-9 rounded-lg flex items-center justify-center transition-colors cursor-pointer no-underline',
  'bg-white/95 hover:bg-white text-slate-900 border border-slate-300',
  'dark:bg-slate-800 dark:hover:bg-slate-700 dark:text-white dark:border-transparent',
].join(' ');
const actionIcon = 'w-4 h-4';
</script>

<template>
  <div
    v-if="media"
    class="fixed inset-0 z-[99999] bg-black/90 backdrop-blur-sm flex flex-col"
    @click.self="emit('close')"
  >
    <div class="flex items-center justify-end px-6 py-4 gap-2">
      <a
        :href="media.url"
        target="_blank"
        rel="noopener noreferrer"
        :title="t('PATIENT_EXAMS.LIGHTBOX.DOWNLOAD')"
        :class="actionBtn"
      >
        <i :class="['i-lucide-download', actionIcon]" />
      </a>
      <button
        type="button"
        :title="t('PATIENT_EXAMS.LIGHTBOX.CLOSE')"
        :class="actionBtn"
        @click="emit('close')"
      >
        <i :class="['i-lucide-x', actionIcon]" />
      </button>
    </div>
    <div class="flex-1 flex items-center justify-center p-4 overflow-hidden">
      <template v-if="isPdf(media)">
        <!-- Sem `sandbox`: Chrome PDF viewer interno (extensão chrome-pdf)
             não carrega em iframes sandboxados, mesmo com allow-scripts.
             O conteúdo é same-origin (streamado pelo Rails via
             SecureBlobsController) e o token JÁ foi validado pelo
             cross-tenant guard antes de chegar aqui — não há valor de
             segurança adicional em sandboxar este iframe específico. -->
        <iframe
          :src="media.url"
          class="w-full h-full rounded-lg bg-white"
          style="max-height: calc(100vh - 120px)"
          referrerpolicy="no-referrer"
          :title="t('PATIENT_EXAMS.LIGHTBOX.PDF_TITLE')"
        />
      </template>
      <template v-else-if="isVideo(media)">
        <video
          :src="media.url"
          class="max-w-full max-h-full rounded-lg bg-black"
          style="max-height: calc(100vh - 120px)"
          controls
          autoplay
          playsinline
        />
      </template>
      <template v-else>
        <img
          :src="media.url"
          class="max-w-full max-h-full rounded-lg object-contain"
          style="max-height: calc(100vh - 120px)"
        />
      </template>
    </div>
  </div>
</template>
