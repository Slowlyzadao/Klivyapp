<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();
const name = ref('');

watch(
  () => props.open,
  isOpen => {
    if (isOpen) name.value = '';
  }
);

const handleConfirm = () => {
  const trimmed = name.value.trim();
  if (!trimmed) return;
  emit('confirm', trimmed);
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
        <i class="i-lucide-folder-plus text-blue-400" />
        {{ t('PATIENT_EXAMS.MODALS.CREATE_FOLDER.TITLE') }}
      </h3>
      <input
        v-model="name"
        class="record-modal-input w-full rounded-xl px-4 py-2.5 text-sm focus:outline-none mb-4 border"
        :placeholder="t('PATIENT_EXAMS.MODALS.CREATE_FOLDER.PLACEHOLDER')"
        autofocus
        @keyup.enter="handleConfirm"
      />
      <div class="flex gap-3 justify-end">
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EXAMS.MODALS.CREATE_FOLDER.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          size="sm"
          variant="solid"
          color="blue"
          icon="i-lucide-check"
          :label="t('PATIENT_EXAMS.MODALS.CREATE_FOLDER.CREATE')"
          :is-loading="loading"
          :disabled="!name.trim() || loading"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
