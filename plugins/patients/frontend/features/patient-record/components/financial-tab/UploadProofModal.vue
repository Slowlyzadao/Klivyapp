<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';

defineProps({
  open: { type: Boolean, default: false },
  transaction: { type: Object, default: null },
  uploading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'upload']);

const { t } = useI18n();

const handleUpload = event => {
  const file = event.target.files?.[0];
  if (file) emit('upload', file);
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
  >
    <div
      class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
    >
      <div
        class="flex items-center justify-between p-6 border-b border-slate-700/50"
      >
        <div>
          <h3
            class="text-lg font-semibold text-slate-100 flex items-center gap-2"
          >
            <i class="i-lucide-paperclip text-sky-400" />
            {{ t('PATIENT_FINANCIAL.MODALS.PROOF.TITLE') }}
          </h3>
          <p class="text-xs text-slate-400 mt-0.5">
            {{ t('PATIENT_FINANCIAL.MODALS.PROOF.SUBTITLE') }}
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="p-6 space-y-4">
        <div v-if="transaction" class="bg-slate-800 rounded-xl p-4 space-y-1">
          <p class="text-xs text-slate-400">
            {{ t('PATIENT_FINANCIAL.MODALS.PROOF.TRANSACTION') }}
          </p>
          <p class="text-sm font-semibold text-slate-200">
            {{
              transaction.description ||
              t('PATIENT_FINANCIAL.MODALS.PROOF.DEFAULT_DESCRIPTION')
            }}
          </p>
          <p class="text-lg font-bold text-emerald-400">
            {{ formatCurrency(transaction.amount) }}
          </p>
        </div>

        <label class="block">
          <span class="text-sm text-slate-300 mb-2 block">
            {{ t('PATIENT_FINANCIAL.MODALS.PROOF.FILE_LABEL') }}
          </span>
          <div
            class="border-2 border-dashed border-slate-600 hover:border-sky-500 rounded-xl p-8 text-center cursor-pointer transition-colors relative"
          >
            <i
              class="i-lucide-upload-cloud text-3xl text-slate-500 block mb-2"
            />
            <p class="text-sm text-slate-400">
              {{ t('PATIENT_FINANCIAL.MODALS.PROOF.FILE_HINT') }}
            </p>
            <p class="text-xs text-slate-600 mt-1">
              {{ t('PATIENT_FINANCIAL.MODALS.PROOF.FILE_LIMITS') }}
            </p>
            <input
              type="file"
              accept="image/*,application/pdf"
              class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
              :disabled="uploading"
              @change="handleUpload"
            />
          </div>
        </label>

        <div
          v-if="uploading"
          class="flex items-center gap-2 text-sky-400 text-sm"
        >
          <i class="i-lucide-loader-2 animate-spin" />
          {{ t('PATIENT_FINANCIAL.MODALS.PROOF.UPLOADING') }}
        </div>
      </div>
    </div>
  </div>
</template>
