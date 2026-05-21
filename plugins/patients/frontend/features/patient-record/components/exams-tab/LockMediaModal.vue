<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  action: { type: String, default: 'lock' }, // 'lock' | 'unlock'
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();

const isLock = computed(() => props.action === 'lock');
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
    @click.self="!loading && emit('close')"
  >
    <div
      class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
    >
      <div class="flex items-center gap-3 mb-4">
        <div
          class="w-10 h-10 rounded-full flex items-center justify-center"
          :class="
            isLock
              ? 'bg-amber-500/10 border border-amber-500/20'
              : 'bg-emerald-500/10 border border-emerald-500/20'
          "
        >
          <i
            :class="
              isLock
                ? 'i-lucide-lock text-amber-400'
                : 'i-lucide-unlock text-emerald-400'
            "
            class="text-lg"
          />
        </div>
        <h3 class="text-lg font-semibold text-slate-100">
          {{
            isLock
              ? t('PATIENT_EXAMS.MODALS.LOCK_MEDIA.LOCK_TITLE')
              : t('PATIENT_EXAMS.MODALS.LOCK_MEDIA.UNLOCK_TITLE')
          }}
        </h3>
      </div>
      <p class="text-sm text-slate-400 mb-5">
        {{
          isLock
            ? t('PATIENT_EXAMS.MODALS.LOCK_MEDIA.LOCK_MESSAGE')
            : t('PATIENT_EXAMS.MODALS.LOCK_MEDIA.UNLOCK_MESSAGE')
        }}
      </p>
      <div class="flex gap-3 justify-end">
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EXAMS.MODALS.LOCK_MEDIA.CANCEL')"
          :disabled="loading"
          @click="emit('close')"
        />
        <BeclinicButton
          size="sm"
          variant="solid"
          :color="isLock ? 'amber' : 'teal'"
          :icon="isLock ? 'i-lucide-lock' : 'i-lucide-unlock'"
          :label="t('PATIENT_EXAMS.MODALS.LOCK_MEDIA.CONFIRM')"
          :is-loading="loading"
          :disabled="loading"
          @click="emit('confirm')"
        />
      </div>
    </div>
  </div>
</template>
