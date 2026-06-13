<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import {
  isImage,
  isVideo,
  isPdf,
} from '@plugins/patients/frontend/features/patient-record/utils/examClassifiers';

const props = defineProps({
  media: { type: Object, required: true },
  isDragging: { type: Boolean, default: false },
  isRenaming: { type: Boolean, default: false },
});

const thumbReady = ref(false);
const thumbFailed = ref(false);

const thumbSrc = computed(() =>
  isImage(props.media) ? props.media.thumbnail_url || props.media.url : null
);

const needsThumbSpinner = computed(
  () => (isImage(props.media) || isVideo(props.media)) && !thumbReady.value && !thumbFailed.value
);

watch(
  () => [thumbSrc.value, props.media.url],
  () => {
    thumbReady.value = false;
    thumbFailed.value = false;
  }
);

const onThumbLoaded = () => {
  thumbReady.value = true;
};
const onThumbError = () => {
  thumbFailed.value = true;
};

const emit = defineEmits([
  'drag-start',
  'drag-end',
  'open-lightbox',
  'start-rename',
  'confirm-rename',
  'cancel-rename',
  'lock',
  'unlock',
  'delete',
]);

const { t } = useI18n();

const renameValue = ref(props.media.file_name || '');
watch(
  () => props.isRenaming,
  v => {
    if (v) renameValue.value = props.media.file_name || '';
  }
);

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const onConfirmRename = () => emit('confirm-rename', renameValue.value);
</script>

<template>
  <div
    class="exams-card group relative"
    :class="{
      'exams-card--locked': media.locked,
      'exam-card-dragging': isDragging,
    }"
    draggable="true"
    @dragstart="emit('drag-start', $event)"
    @dragend="emit('drag-end')"
  >
    <div
      v-if="media.locked"
      class="exams-lock-badge"
      :title="t('PATIENT_EXAMS.CARD.LOCK_BADGE')"
    >
      <i class="i-lucide-lock text-[10px] text-white" />
    </div>

    <div class="exams-thumb" @click="emit('open-lightbox', media)">
      <video
        v-if="isVideo(media) && media.url"
        :src="media.url"
        class="object-cover w-full h-full"
        preload="metadata"
        muted
        playsinline
        @loadedmetadata="onThumbLoaded"
        @error="onThumbError"
      />
      <img
        v-else-if="isImage(media) && thumbSrc"
        :src="thumbSrc"
        class="object-cover w-full h-full"
        loading="lazy"
        @load="onThumbLoaded"
        @error="onThumbError"
      />
      <div v-else-if="isPdf(media)" class="exams-thumb-pdf">
        <div class="exams-thumb-pdf-icon">
          <i class="i-lucide-file-text w-7 h-7 text-red-400" />
        </div>
        <span class="exams-thumb-pdf-label">PDF</span>
      </div>
      <i v-else class="i-lucide-file text-slate-600 text-4xl" />

      <div
        v-if="needsThumbSpinner"
        class="absolute inset-0 flex items-center justify-center pointer-events-none bg-slate-100/40 dark:bg-slate-900/30"
        aria-hidden="true"
      >
        <span class="inline-block w-6 h-6 rounded-full border-2 border-slate-300/60 dark:border-slate-500/60 border-t-blue-500 dark:border-t-blue-400 animate-spin" />
      </div>
      <div
        v-if="thumbFailed && (isImage(media) || isVideo(media))"
        class="absolute inset-0 flex items-center justify-center pointer-events-none"
      >
        <i class="i-lucide-image-off text-slate-400 text-2xl" />
      </div>

      <div v-if="isVideo(media)" class="exams-thumb-badge">
        <i class="i-lucide-play w-3 h-3" />
        <span>{{ t('PATIENT_EXAMS.CARD.VIDEO_BADGE') }}</span>
      </div>

      <div class="exams-thumb-overlay">
        <div class="exams-thumb-eye">
          <i class="i-lucide-eye w-4 h-4" />
        </div>
      </div>
    </div>

    <div class="exams-card-footer">
      <div v-if="isRenaming" class="flex items-center gap-1 mb-1.5">
        <input
          v-model="renameValue"
          class="flex-1 h-6 bg-white dark:bg-slate-700 border border-slate-300 dark:border-slate-600 rounded px-1.5 text-[11px] text-slate-800 dark:text-slate-100 focus:outline-none focus:border-blue-500 dark:focus:border-blue-500 min-w-0"
          autofocus
          @keyup.enter="onConfirmRename"
          @keyup.escape="emit('cancel-rename')"
          @click.stop
        />
        <button
          class="h-6 w-6 p-0 flex items-center justify-center bg-blue-600 hover:bg-blue-500 rounded text-white shrink-0"
          @click.stop="onConfirmRename"
        >
          <i class="i-lucide-check text-base leading-none" />
        </button>
      </div>
      <div v-else class="exams-card-name-row">
        <span class="exams-card-name">
          {{ media.file_name || t('PATIENT_EXAMS.CARD.DEFAULT_NAME') }}
        </span>
        <span v-if="media.created_at" class="exams-card-date">
          {{ formatDate(media.created_at) }}
        </span>
      </div>

      <div class="exams-card-actions">
        <span class="exams-card-category">{{ media.category }}</span>
        <button
          class="exams-card-btn"
          :title="t('PATIENT_EXAMS.CARD.RENAME_TITLE')"
          @click.stop="emit('start-rename', media)"
        >
          <i class="i-lucide-pencil w-3 h-3" />
        </button>
        <a
          :href="media.url"
          :download="media.file_name || 'arquivo'"
          class="exams-card-btn"
          :title="t('PATIENT_EXAMS.CARD.DOWNLOAD_TITLE')"
          @click.stop
        >
          <i class="i-lucide-download w-3 h-3" />
        </a>
        <button
          v-if="!media.locked"
          class="exams-card-btn"
          :title="t('PATIENT_EXAMS.CARD.LOCK_TITLE')"
          @click.stop="emit('lock', media.id)"
        >
          <i class="i-lucide-unlock w-3 h-3" />
        </button>
        <button
          v-else
          class="exams-card-btn exams-card-btn--locked"
          :title="t('PATIENT_EXAMS.CARD.UNLOCK_TITLE')"
          @click.stop="emit('unlock', media.id)"
        >
          <i class="i-lucide-lock w-3 h-3" />
        </button>
        <button
          class="exams-card-btn exams-card-btn--danger"
          :class="{ 'opacity-40 cursor-not-allowed': media.locked }"
          :title="t('PATIENT_EXAMS.CARD.DELETE_TITLE')"
          @click.stop="emit('delete', media)"
        >
          <i class="i-lucide-trash-2 w-3 h-3" />
        </button>
      </div>
    </div>
  </div>
</template>
