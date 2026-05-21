<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  htmlContent: { type: String, default: '' },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const previewIframe = ref(null);

const triggerPrint = () => {
  previewIframe.value?.contentWindow?.print();
};
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
          <i class="i-lucide-printer text-n-blue-9" />
          {{ title }}
        </h3>
        <div class="flex items-center gap-3">
          <BeclinicButton
            size="sm"
            variant="solid"
            color="slate"
            icon="i-lucide-printer"
            :label="t('PATIENT_FINANCIAL.MODALS.PRINT.PRINT_PDF')"
            @click="triggerPrint"
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
          ref="previewIframe"
          :srcdoc="htmlContent"
          class="w-full h-full border-none bg-white block absolute inset-0"
          title="Visualização de Impressão"
          sandbox="allow-same-origin allow-modals"
          referrerpolicy="no-referrer"
        />
      </div>
    </div>
  </div>
</template>
