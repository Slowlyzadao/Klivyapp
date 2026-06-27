<script setup>
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  open: { type: Boolean, default: false },
  folder: { type: Object, default: null },
  blockedMessage: { type: String, default: '' },
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
    <div class="record-modal-box rounded-2xl shadow-xl w-full max-w-sm p-6 border">
      <!-- Bloqueado -->
      <template v-if="blockedMessage">
        <div class="flex items-center gap-3 mb-4">
          <div
            class="w-10 h-10 rounded-full bg-amber-500/10 border border-amber-500/20 flex items-center justify-center"
          >
            <i class="i-lucide-lock text-amber-400 text-lg" />
          </div>
          <h3 class="text-lg font-semibold text-amber-300">
            {{ t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.BLOCKED_TITLE') }}
          </h3>
        </div>
        <p class="record-modal-muted text-sm mb-5">{{ blockedMessage }}</p>
        <div class="flex justify-end">
          <BeclinicButton
            size="sm"
            variant="solid"
            color="amber"
            :label="t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.BLOCKED_OK')"
            @click="emit('close')"
          />
        </div>
      </template>

      <!-- Exclusão normal -->
      <template v-else>
        <div class="flex items-center gap-3 mb-4">
          <div
            class="w-10 h-10 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center"
          >
            <i class="i-lucide-folder-minus text-red-400 text-lg" />
          </div>
          <h3 class="record-modal-title text-lg font-semibold">
            {{ t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.TITLE') }}
          </h3>
        </div>
        <p class="record-modal-muted text-sm mb-5">
          {{ t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.CONFIRM_PREFIX') }}
          <strong class="record-modal-title">"{{ folder?.name }}"</strong>
          {{ t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.CONFIRM_SUFFIX') }}
        </p>
        <div class="flex gap-3 justify-end">
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            :label="t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.CANCEL')"
            @click="emit('close')"
          />
          <BeclinicButton
            size="sm"
            variant="solid"
            color="ruby"
            :label="t('PATIENT_EXAMS.MODALS.DELETE_FOLDER.DELETE')"
            @click="emit('confirm')"
          />
        </div>
      </template>
    </div>
  </div>
</template>
