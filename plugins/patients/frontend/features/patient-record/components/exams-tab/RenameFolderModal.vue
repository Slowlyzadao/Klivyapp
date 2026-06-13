<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  FOLDER_COLORS,
  DEFAULT_FOLDER_COLOR,
} from '@plugins/patients/frontend/constants/exams';

const props = defineProps({
  open: { type: Boolean, default: false },
  folder: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();
const name = ref('');
const color = ref(DEFAULT_FOLDER_COLOR);

watch(
  () => props.open,
  isOpen => {
    if (isOpen && props.folder) {
      name.value = props.folder.name || '';
      color.value = props.folder.color || DEFAULT_FOLDER_COLOR;
    }
  }
);

const handleConfirm = () => {
  const trimmed = name.value.trim();
  if (!trimmed) return;
  emit('confirm', { name: trimmed, color: color.value });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div class="record-modal-box rounded-2xl shadow-xl w-full max-w-sm p-6 border">
      <h3
        class="record-modal-title text-lg font-semibold mb-4 flex items-center gap-2"
      >
        <i class="i-lucide-pencil text-blue-400" />
        {{ t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.TITLE') }}
      </h3>

      <label class="record-modal-label text-xs font-medium mb-1 block">
        {{ t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.NAME_LABEL') }}
      </label>
      <input
        v-model="name"
        class="record-modal-input w-full rounded-xl px-4 py-2.5 text-sm focus:outline-none mb-4 border"
        :placeholder="t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.PLACEHOLDER')"
        autofocus
        @keyup.enter="handleConfirm"
      />

      <label class="record-modal-label text-xs font-medium mb-2 block">
        {{ t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.COLOR_LABEL') }}
      </label>
      <div class="flex flex-wrap gap-2 mb-5">
        <button
          v-for="opt in FOLDER_COLORS"
          :key="opt.value"
          class="w-7 h-7 rounded-full border-2 transition-all hover:scale-110 focus:outline-none"
          :style="{
            backgroundColor: opt.value,
            borderColor: color === opt.value ? '#fff' : 'transparent',
          }"
          :title="opt.label"
          @click="color = opt.value"
        />
      </div>

      <div
        class="record-modal-preview flex items-center gap-2 mb-4 px-3 py-2 rounded-xl border"
      >
        <i class="i-lucide-folder text-lg" :style="{ color }" />
        <span class="text-sm font-medium" :style="{ color }">
          {{ name || t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.PREVIEW_DEFAULT') }}
        </span>
      </div>

      <div class="flex gap-3 justify-end">
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          size="sm"
          variant="solid"
          color="blue"
          icon="i-lucide-check"
          :label="t('PATIENT_EXAMS.MODALS.RENAME_FOLDER.SAVE')"
          :disabled="!name.trim()"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
