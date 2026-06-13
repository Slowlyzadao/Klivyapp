<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { FILE_INPUT_ACCEPT } from '@plugins/patients/frontend/constants/exams';

defineProps({
  isUploading: { type: Boolean, default: false },
  uploadProgress: { type: Number, default: 0 },
});

const emit = defineEmits(['create-folder', 'file-selected']);

const { t } = useI18n();
const fileInput = ref(null);

const triggerUpload = () => fileInput.value?.click();

const handleFileChange = event => {
  const file = event.target.files?.[0];
  if (file) emit('file-selected', file);
  // eslint-disable-next-line no-param-reassign
  event.target.value = null;
};
</script>

<template>
  <div class="reg-header mb-5">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_EXAMS.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_EXAMS.HEADER.SUBTITLE') }}
      </p>
      <p class="text-xs text-slate-500 mt-1">
        {{ t('PATIENT_EXAMS.HEADER.LIMITS') }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <input
        ref="fileInput"
        type="file"
        class="hidden"
        :accept="FILE_INPUT_ACCEPT"
        @change="handleFileChange"
      />
      <BeclinicButton
        variant="faded"
        color="slate"
        icon="i-lucide-folder-plus"
        :label="t('PATIENT_EXAMS.HEADER.NEW_FOLDER')"
        @click="emit('create-folder')"
      />
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-upload-cloud"
        :is-loading="isUploading"
        :disabled="isUploading"
        :label="
          isUploading
            ? t('PATIENT_EXAMS.HEADER.UPLOAD_PROGRESS', { progress: uploadProgress })
            : t('PATIENT_EXAMS.HEADER.UPLOAD')
        "
        @click="triggerUpload"
      />
    </div>
  </div>
</template>
