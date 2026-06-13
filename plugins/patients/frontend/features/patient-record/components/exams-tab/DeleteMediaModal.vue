<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  open: { type: Boolean, default: false },
  media: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div
      class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
    >
      <div class="flex items-center gap-3 mb-4">
        <div
          class="w-10 h-10 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center"
        >
          <i class="i-lucide-trash-2 text-red-400 text-lg" />
        </div>
        <h3 class="text-lg font-semibold text-slate-100">
          {{ t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.TITLE') }}
        </h3>
      </div>
      <p class="text-sm text-slate-400 mb-5">
        {{ t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.CONFIRM_PREFIX') }}
        <strong class="text-slate-200">
          "{{
            media?.file_name || t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.DEFAULT_NAME')
          }}"
        </strong>
        {{ t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.CONFIRM_SUFFIX') }}
      </p>
      <div class="flex gap-3 justify-end">
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          size="sm"
          variant="solid"
          color="ruby"
          :label="
            loading
              ? t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.DELETING')
              : t('PATIENT_EXAMS.MODALS.DELETE_MEDIA.DELETE')
          "
          :is-loading="loading"
          :disabled="loading"
          @click="emit('confirm')"
        />
      </div>
    </div>
  </div>
</template>
