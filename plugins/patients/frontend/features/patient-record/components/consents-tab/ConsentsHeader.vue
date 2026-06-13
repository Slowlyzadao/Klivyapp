<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  formOpen: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle-form']);

const { t } = useI18n();
</script>

<template>
  <div class="reg-header mb-5">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_CONSENTS.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_CONSENTS.HEADER.SUBTITLE') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <BeclinicButton
        variant="solid"
        :color="formOpen ? 'slate' : 'teal'"
        :icon="formOpen ? 'i-lucide-x' : 'i-lucide-plus'"
        :label="
          formOpen
            ? t('PATIENT_CONSENTS.HEADER.CANCEL')
            : t('PATIENT_CONSENTS.HEADER.NEW')
        "
        @click="emit('toggle-form')"
      />
    </div>
  </div>
</template>
