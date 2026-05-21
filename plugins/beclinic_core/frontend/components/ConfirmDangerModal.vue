<script setup>
/**
 * ConfirmDangerModal — Modal genérico de confirmação para ações destrutivas
 * (excluir, revogar, arquivar). Substitui a duplicação dos modais inline
 * espalhados pelos plugins (TreatmentPlanTab tinha 2, ExamsTab/Documents/etc.).
 *
 * Uso:
 *   <ConfirmDangerModal
 *     v-model:show="showConfirmDelete"
 *     title="Excluir item?"
 *     message="Esta ação não pode ser desfeita."
 *     confirm-label="Excluir"
 *     :loading="isDeleting"
 *     @confirm="handleConfirm"
 *   />
 *
 * O slot `default` permite mensagens com markup mais rico (links, listas).
 */
import BeclinicButton from './Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  title: { type: String, required: true },
  message: { type: String, default: '' },
  confirmLabel: { type: String, default: 'Confirmar' },
  cancelLabel: { type: String, default: 'Cancelar' },
  loading: { type: Boolean, default: false },
  // Esconde overlay click + botões durante loading para evitar dispatch dupla.
  blockingLoading: { type: Boolean, default: true },
});

const emit = defineEmits(['update:show', 'confirm', 'cancel']);

const close = () => {
  if (props.loading && props.blockingLoading) return;
  emit('update:show', false);
  emit('cancel');
};

const onConfirm = () => {
  if (props.loading) return;
  emit('confirm');
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <Teleport to="body">
    <div
      v-if="show"
      class="cdm-overlay"
      role="dialog"
      aria-modal="true"
      @click.self="close"
    >
      <div class="cdm-card">
        <div class="cdm-body">
          <div class="cdm-icon-wrap">
            <i class="i-lucide-alert-triangle cdm-icon" />
          </div>
          <div class="cdm-text">
            <h3 class="cdm-title">{{ title }}</h3>
            <p v-if="message" class="cdm-message">{{ message }}</p>
            <slot />
          </div>
        </div>
        <div class="cdm-footer">
          <BeclinicButton
            type="button"
            variant="ghost"
            color="slate"
            :label="cancelLabel"
            :disabled="loading && blockingLoading"
            @click="close"
          />
          <BeclinicButton
            type="button"
            variant="solid"
            color="ruby"
            :label="confirmLabel"
            :is-loading="loading"
            :disabled="loading"
            @click="onConfirm"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* Dual-theme: usa tokens do projeto (rgb(var(--slate-N))) — funciona
   em light e dark mode sem cores hardcoded. */
.cdm-overlay {
  position: fixed;
  inset: 0;
  z-index: 99999;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
  backdrop-filter: blur(4px);
  padding: 16px;
}

.cdm-card {
  width: 100%;
  max-width: 440px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 16px;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
  overflow: hidden;
}

.cdm-body {
  padding: 22px 22px 16px;
  display: flex;
  align-items: flex-start;
  gap: 14px;
}

.cdm-icon-wrap {
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: rgba(220, 38, 38, 0.12);
  display: flex;
  align-items: center;
  justify-content: center;
}

.cdm-icon {
  width: 20px;
  height: 20px;
  color: #dc2626;
}

.cdm-text {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding-top: 2px;
  min-width: 0;
}

.cdm-title {
  margin: 0;
  font-weight: 600;
  font-size: 16px;
  line-height: 1.4;
  color: rgb(var(--slate-12));
}

.cdm-message {
  margin: 0;
  font-size: 13px;
  line-height: 1.5;
  color: rgb(var(--slate-9));
}

.cdm-footer {
  padding: 14px 22px;
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
}

@media (max-width: 480px) {
  .cdm-overlay {
    padding: 0;
    align-items: flex-end;
  }

  .cdm-card {
    max-width: 100%;
    border-radius: 16px 16px 0 0;
  }
}
</style>
