<script setup>
import { onBeforeUnmount, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { useCameraCapture } from '@plugins/patients/frontend/features/patient-record/composables/useCameraCapture';

const props = defineProps({
  open: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'use-photo']);

const { t } = useI18n();

const {
  videoElement,
  canvasElement,
  cameraError,
  capturedPhoto,
  startCamera,
  stopCamera,
  capturePhoto,
  retakePhoto,
  dataUrlToFile,
  reset,
} = useCameraCapture();

watch(
  () => props.open,
  async isOpen => {
    if (isOpen) {
      reset();
      await nextTick();
      startCamera();
    } else {
      stopCamera();
      reset();
    }
  }
);

onBeforeUnmount(() => stopCamera());

const handleClose = () => emit('close');

const handleUse = async () => {
  if (!capturedPhoto.value) return;
  const file = await dataUrlToFile(capturedPhoto.value);
  emit('use-photo', file);
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-[99999] flex items-center justify-center bg-black/75 backdrop-blur-md px-4"
    @click.self="handleClose"
  >
    <div class="cam-modal">
      <!-- Header -->
      <div class="cam-modal-header">
        <div class="flex items-center gap-2.5">
          <div class="cam-header-icon">
            <i class="i-lucide-camera w-4 h-4" />
          </div>
          <div>
            <p class="text-sm font-semibold text-n-slate-12 leading-none">
              {{ t('PATIENT_REGISTRATION.CAMERA_MODAL.TITLE') }}
            </p>
            <p class="text-xs text-n-slate-10 mt-0.5">
              {{ t('PATIENT_REGISTRATION.CAMERA_MODAL.SUBTITLE') }}
            </p>
          </div>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="handleClose"
        />
      </div>

      <!-- Viewfinder -->
      <div class="cam-viewfinder">
        <video
          v-show="!capturedPhoto"
          ref="videoElement"
          class="cam-video"
          autoplay
          playsinline
        />
        <img v-show="capturedPhoto" :src="capturedPhoto" class="cam-video" />
        <canvas ref="canvasElement" class="hidden" />

        <div v-if="!capturedPhoto && !cameraError" class="cam-guide-overlay">
          <div class="cam-guide-ring" />
        </div>

        <div v-if="cameraError" class="cam-error-overlay">
          <i class="i-lucide-camera-off w-10 h-10 text-n-red-10 dark:text-n-red-9 mb-3" />
          <p class="text-sm text-n-slate-11 text-center px-4">
            {{ t('PATIENT_REGISTRATION.CAMERA_MODAL.ERROR') }}
          </p>
        </div>
      </div>

      <!-- Controles -->
      <div class="cam-controls">
        <template v-if="!capturedPhoto">
          <BeclinicButton
            variant="ghost"
            color="slate"
            :label="t('PATIENT_REGISTRATION.CAMERA_MODAL.CANCEL')"
            @click="handleClose"
          />
          <button
            class="cam-btn-capture"
            :disabled="cameraError"
            @click="capturePhoto"
          >
            <span class="cam-shutter" />
          </button>
          <div class="w-20" />
        </template>
        <template v-else>
          <BeclinicButton
            variant="ghost"
            color="slate"
            icon="i-lucide-refresh-cw"
            :label="t('PATIENT_REGISTRATION.CAMERA_MODAL.RETAKE')"
            @click="retakePhoto"
          />
          <BeclinicButton
            variant="solid"
            color="blue"
            icon="i-lucide-check"
            :label="t('PATIENT_REGISTRATION.CAMERA_MODAL.USE_PHOTO')"
            @click="handleUse"
          />
        </template>
      </div>
    </div>
  </div>
</template>
