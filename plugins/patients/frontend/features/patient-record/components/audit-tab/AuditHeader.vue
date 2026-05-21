<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  isExporting: { type: Boolean, default: false },
});

const emit = defineEmits(['export']);

const { t } = useI18n();
</script>

<template>
  <div class="reg-header mb-6">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_AUDIT.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_AUDIT.HEADER.SUBTITLE') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <BeclinicButton
        variant="faded"
        color="slate"
        icon="i-lucide-download"
        :label="
          isExporting
            ? t('PATIENT_AUDIT.HEADER.EXPORTING')
            : t('PATIENT_AUDIT.HEADER.EXPORT_PDF')
        "
        :is-loading="isExporting"
        :disabled="isExporting"
        @click="emit('export')"
      />
    </div>
  </div>
</template>
