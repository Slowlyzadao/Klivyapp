<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const emit = defineEmits(['generate']);

const { t } = useI18n();
</script>

<template>
  <div class="reg-header mb-5">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_DOCUMENTS.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_DOCUMENTS.HEADER.SUBTITLE') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-file-plus"
        :label="t('PATIENT_DOCUMENTS.HEADER.GENERATE')"
        @click="emit('generate')"
      />
    </div>
  </div>
</template>
