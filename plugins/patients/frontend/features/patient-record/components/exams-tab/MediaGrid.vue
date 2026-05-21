<script setup>
import { useI18n } from 'vue-i18n';
import MediaCard from './MediaCard.vue';

defineProps({
  medias: { type: Array, default: () => [] },
  draggedMediaId: { type: [Number, String, null], default: null },
  renamingMediaId: { type: [Number, String, null], default: null },
});

const emit = defineEmits([
  'media-drag-start',
  'media-drag-end',
  'open-lightbox',
  'start-rename',
  'confirm-rename',
  'cancel-rename',
  'lock',
  'unlock',
  'delete',
]);

const { t } = useI18n();
</script>

<template>
  <div v-if="medias.length === 0" class="exams-empty-state">
    <div class="exams-empty-icon">
      <i class="i-lucide-folder-open w-6 h-6" />
    </div>
    <p class="exams-empty-text">{{ t('PATIENT_EXAMS.EMPTY.TITLE') }}</p>
    <p class="exams-empty-hint">{{ t('PATIENT_EXAMS.EMPTY.HINT') }}</p>
  </div>

  <div
    v-else
    class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3"
  >
    <MediaCard
      v-for="media in medias"
      :key="media.id"
      :media="media"
      :is-dragging="draggedMediaId === media.id"
      :is-renaming="renamingMediaId === media.id"
      @drag-start="$event => emit('media-drag-start', $event, media.id)"
      @drag-end="emit('media-drag-end')"
      @open-lightbox="$event => emit('open-lightbox', $event)"
      @start-rename="$event => emit('start-rename', $event)"
      @confirm-rename="value => emit('confirm-rename', value)"
      @cancel-rename="emit('cancel-rename')"
      @lock="id => emit('lock', id)"
      @unlock="id => emit('unlock', id)"
      @delete="$event => emit('delete', $event)"
    />
  </div>
</template>
