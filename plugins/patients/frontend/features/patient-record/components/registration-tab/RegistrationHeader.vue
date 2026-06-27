<script setup>
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  updatedAt: { type: String, default: '' },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';
</script>

<template>
  <div class="reg-header mb-5">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_REGISTRATION.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_REGISTRATION.HEADER.SUBTITLE') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <span class="text-xs text-slate-500">
        {{
          t('PATIENT_REGISTRATION.HEADER.LAST_UPDATED', {
            date: formatDate(updatedAt),
          })
        }}
      </span>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-save"
        :label="t('PATIENT_REGISTRATION.HEADER.SAVE')"
        :is-loading="isLoading"
        :disabled="isLoading"
        @click="emit('save')"
      />
    </div>
  </div>
</template>
