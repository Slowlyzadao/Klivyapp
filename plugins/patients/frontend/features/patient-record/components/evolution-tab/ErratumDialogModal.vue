<script setup>
/**
 * ErratumDialogModal — modal "Marcar errata".
 *
 * Confirmação destrutiva específica de SessionLog: requer justificativa
 * mínima (2 chars) para registrar errata. Diferente do ConfirmDangerModal
 * porque precisa de campo de input — por isso não usamos o modal genérico.
 *
 * Extraído de EvolutionTab.vue em [1.5.2.6] (Fase 4 do roadmap).
 */
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();

const reason = ref('');

watch(
  () => props.open,
  isOpen => {
    if (isOpen) reason.value = '';
  }
);

const handleConfirm = () => {
  const trimmed = reason.value.trim();
  if (!trimmed) return;
  emit('confirm', trimmed);
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
  >
    <div class="evo-erratum-modal">
      <div class="evo-modal-header">
        <h4 class="text-base font-semibold text-slate-100">
          {{ t('PATIENT_EVOLUTION.ERRATUM_DIALOG.TITLE') }}
        </h4>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>
      <div class="evo-modal-body">
        <p class="evo-erratum-warning">
          {{ t('PATIENT_EVOLUTION.ERRATUM_DIALOG.DESCRIPTION') }}
        </p>
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_EVOLUTION.ERRATUM_DIALOG.REASON_LABEL') }}
          </label>
          <textarea
            v-model="reason"
            class="form-input form-textarea"
            rows="4"
            :placeholder="t('PATIENT_EVOLUTION.ERRATUM_DIALOG.REASON_PLACEHOLDER')"
          />
        </div>
      </div>
      <div class="evo-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EVOLUTION.ERRATUM_DIALOG.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="ruby"
          :label="t('PATIENT_EVOLUTION.ERRATUM_DIALOG.CONFIRM')"
          :is-loading="loading"
          :disabled="loading || !reason.trim()"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
