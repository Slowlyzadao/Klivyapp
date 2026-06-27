<script setup>
/**
 * DocumentPreviewModal — preview de PDF de documento gerado.
 *
 * Renderiza o PDF (`secure_blobs/<token>` same-origin via send_data) num iframe
 * dentro de um modal grande. Usado pra evitar baixar o arquivo só pra conferir
 * o conteúdo.
 *
 * O backend [`SecureBlobsController`] já serve PDFs com `disposition: :inline`
 * via `send_data` same-origin, então o iframe consegue renderizar usando o
 * visualizador nativo do browser.
 */
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  src: { type: String, default: '' },
});

const emit = defineEmits(['close', 'download']);

const { t } = useI18n();
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-[60] flex items-center justify-center p-0 sm:p-4 bg-black/80 backdrop-blur-sm"
  >
    <div
      class="bg-n-background sm:border sm:border-n-strong sm:rounded-xl shadow-2xl w-full h-full sm:max-w-4xl sm:h-[90vh] flex flex-col overflow-hidden relative"
    >
      <div
        class="flex items-center justify-between px-4 py-3 border-b border-n-strong flex-shrink-0"
      >
        <h3
          class="text-base font-semibold text-n-slate-12 flex items-center gap-2"
        >
          <i class="i-lucide-file-text text-n-blue-9" />
          {{ title || t('PATIENT_DOCUMENTS.PREVIEW.TITLE') }}
        </h3>
        <div class="flex items-center gap-3">
          <BeclinicButton
            size="sm"
            variant="solid"
            color="slate"
            icon="i-lucide-download"
            :label="t('PATIENT_DOCUMENTS.PREVIEW.DOWNLOAD')"
            @click="emit('download')"
          />
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            @click="emit('close')"
          />
        </div>
      </div>
      <div class="flex-1 bg-n-slate-2 overflow-hidden relative">
        <iframe
          v-if="src"
          :src="src"
          class="w-full h-full border-none bg-white block absolute inset-0"
          :title="title || t('PATIENT_DOCUMENTS.PREVIEW.TITLE')"
          referrerpolicy="no-referrer"
        />
        <div
          v-else
          class="absolute inset-0 flex items-center justify-center text-n-slate-9"
        >
          <i class="i-lucide-loader-2 w-6 h-6 animate-spin" />
        </div>
      </div>
    </div>
  </div>
</template>
