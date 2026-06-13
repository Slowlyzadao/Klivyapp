<script setup>
/**
 * Modal genérico de confirmação destrutiva (substitui window.confirm nativo).
 *
 * Padroniza o look-and-feel de "tem certeza?" em todo o módulo financeiro.
 * Aceita texto livre (com support a strong/em via slot) ou message string.
 *
 * Props:
 *   - show: Boolean
 *   - title: String                 — ex.: "Inativar perfil financeiro?"
 *   - message: String               — corpo de texto (alternativa ao slot default)
 *   - confirmLabel: String          — texto do botão de confirmar (default: "Confirmar")
 *   - cancelLabel: String           — default: "Cancelar"
 *   - tone: 'danger' | 'warn'       — default: 'warn'
 *   - icon: String                  — lucide icon (default por tone)
 *
 * Slot default permite HTML rico (`<strong>`, `<em>`, `<br>`).
 *
 * Eventos:
 *   - close (cancelado)
 *   - confirm
 */
import { computed } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  title: { type: String, required: true },
  message: { type: String, default: '' },
  confirmLabel: { type: String, default: 'Confirmar' },
  cancelLabel: { type: String, default: 'Cancelar' },
  tone: { type: String, default: 'warn' }, // 'danger' | 'warn'
  icon: { type: String, default: '' },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const toneIcon = computed(() => {
  if (props.icon) return props.icon;
  return props.tone === 'danger' ? 'i-lucide-octagon-alert' : 'i-lucide-alert-triangle';
});

const toneClass = computed(() => `cdm-v2--${props.tone}`);

const confirmColor = computed(() => props.tone === 'danger' ? 'ruby' : 'amber');

function close() {
  if (props.loading) return;
  emit('close');
}

function onConfirm() {
  if (props.loading) return;
  emit('confirm');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="cdm-v2__backdrop">
      <div class="cdm-v2__modal" :class="toneClass" role="dialog" aria-modal="true">
        <div class="cdm-v2__body">
          <div class="cdm-v2__icon-wrap">
            <i :class="toneIcon" class="cdm-v2__icon" />
          </div>
          <h2 class="cdm-v2__title">{{ title }}</h2>
          <div class="cdm-v2__message">
            <slot>{{ message }}</slot>
          </div>
        </div>

        <footer class="cdm-v2__footer">
          <BeclinicButton variant="ghost" color="slate" :label="cancelLabel" :disabled="loading" @click="close" />
          <BeclinicButton
            variant="solid"
            :color="confirmColor"
            :label="confirmLabel"
            :is-loading="loading"
            :disabled="loading"
            @click="onConfirm"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
.cdm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center;
  z-index: 10000;
  padding: 16px;
}

.cdm-v2__modal {
  width: min(440px, 100%);
  background: rgb(var(--slate-1));
  border-radius: 16px;
  border: 1px solid rgb(var(--slate-4));
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  display: flex; flex-direction: column;
  overflow: hidden;
}

.cdm-v2__body {
  padding: 24px 24px 18px;
  display: flex; flex-direction: column; align-items: center;
  text-align: center; gap: 12px;
}

.cdm-v2__icon-wrap {
  width: 48px; height: 48px;
  display: flex; align-items: center; justify-content: center;
  border-radius: 50%;
  background: rgba(245, 158, 11, 0.12);

  .cdm-v2--danger & {
    background: rgba(244, 63, 94, 0.12);
  }
}
.cdm-v2__icon {
  width: 24px; height: 24px;
  color: rgb(var(--amber-10));

  .cdm-v2--danger & { color: rgb(var(--ruby-10)); }
}

.cdm-v2__title {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.cdm-v2__message {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-10));
  line-height: 1.55;
  max-width: 360px;

  :deep(strong) {
    color: rgb(var(--slate-12));
    font-weight: 600;
  }
}

.cdm-v2__footer {
  display: flex;
  justify-content: center;
  gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
