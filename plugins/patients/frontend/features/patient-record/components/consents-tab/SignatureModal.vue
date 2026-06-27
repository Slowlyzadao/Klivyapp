<script setup>
import { watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { useSignatureCanvas } from '@plugins/patients/frontend/features/patient-record/composables/useSignatureCanvas';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();

const {
  canvasRef,
  hasSignature,
  startDrawing,
  draw,
  stopDrawing,
  clear,
  toDataURL,
} = useSignatureCanvas();

watch(
  () => props.open,
  async isOpen => {
    if (isOpen) {
      await nextTick();
      clear();
    }
  }
);

const handleConfirm = () => {
  if (!hasSignature.value) return;
  emit('confirm', toDataURL('image/webp', 0.85));
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
    @click.self="emit('close')"
  >
    <div class="consent-sign-modal">
      <div class="docs-modal-header">
        <div class="flex items-center gap-3">
          <div class="consent-modal-icon consent-modal-icon--green">
            <i class="i-lucide-pen-tool w-4 h-4" />
          </div>
          <div>
            <h4 class="text-base font-semibold text-slate-100">
              {{ t('PATIENT_CONSENTS.SIGN_MODAL.TITLE') }}
            </h4>
            <p class="text-xs text-slate-500 mt-0.5">
              {{ t('PATIENT_CONSENTS.SIGN_MODAL.SUBTITLE') }}
            </p>
          </div>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="docs-modal-body">
        <div class="consent-canvas-wrap">
          <canvas
            ref="canvasRef"
            width="600"
            height="200"
            class="consent-canvas"
            @mousedown="startDrawing"
            @mousemove="draw"
            @mouseup="stopDrawing"
            @mouseleave="stopDrawing"
            @touchstart.prevent="startDrawing"
            @touchmove.prevent="draw"
            @touchend="stopDrawing"
          />
          <div v-if="!hasSignature" class="consent-canvas-hint">
            <i class="i-lucide-pen-line w-5 h-5 mb-1" />
            <p>{{ t('PATIENT_CONSENTS.SIGN_MODAL.PLACEHOLDER') }}</p>
          </div>
        </div>

        <div class="consent-canvas-footer">
          <BeclinicButton
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-rotate-ccw"
            :label="t('PATIENT_CONSENTS.SIGN_MODAL.CLEAR')"
            @click="clear"
          />
          <p class="consent-hash-hint">
            <i class="i-lucide-shield w-3 h-3" />
            {{ t('PATIENT_CONSENTS.SIGN_MODAL.HASH_HINT') }}
          </p>
        </div>
      </div>

      <div class="docs-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_CONSENTS.SIGN_MODAL.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="teal"
          icon="i-lucide-check-circle"
          :label="t('PATIENT_CONSENTS.SIGN_MODAL.CONFIRM')"
          :is-loading="loading"
          :disabled="loading || !hasSignature"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
