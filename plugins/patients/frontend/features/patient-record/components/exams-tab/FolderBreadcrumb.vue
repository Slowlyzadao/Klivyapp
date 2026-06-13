<script setup>
import { useI18n } from 'vue-i18n';
import { ROOT_FOLDER_ID } from '@plugins/patients/frontend/constants/exams';

defineProps({
  path: { type: Array, default: () => [] },
  activeFolderId: { type: String, default: ROOT_FOLDER_ID },
  fileCount: { type: Number, default: 0 },
  isDragging: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
</script>

<template>
  <div class="exams-breadcrumb">
    <span class="text-slate-500">{{ t('PATIENT_EXAMS.BREADCRUMB.ROOT') }}</span>
    <template v-for="part in path" :key="part.id">
      <i class="i-lucide-chevron-right exams-breadcrumb-sep" />
      <button
        class="exams-breadcrumb-link"
        :style="{ color: part.color || '#94a3b8' }"
        @click="emit('select', part.id)"
      >
        {{ part.name }}
      </button>
    </template>
    <template v-if="activeFolderId === ROOT_FOLDER_ID">
      <i class="i-lucide-chevron-right exams-breadcrumb-sep" />
      <span class="text-slate-300 font-medium">
        {{ t('PATIENT_EXAMS.BREADCRUMB.ALL_FILES') }}
      </span>
    </template>
    <span class="exams-breadcrumb-count">
      {{ t('PATIENT_EXAMS.BREADCRUMB.FILE_COUNT', { count: fileCount }) }}
    </span>
    <span v-if="isDragging" class="exams-drag-hint">
      <i class="i-lucide-arrow-left" />
      {{ t('PATIENT_EXAMS.BREADCRUMB.DRAG_HINT') }}
    </span>
  </div>
</template>
