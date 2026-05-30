<script setup>
// Diálogo de confirmação (substitui window.confirm). Usa o BaseModal do
// design system. Labels e textos vêm por props (plugin-agnóstico).
//
// variant: 'primary' (ação neutra) | 'danger' (ação destrutiva, botão vermelho).

import BaseModal from './BaseModal.vue';

defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  message: { type: String, default: '' },
  confirmLabel: { type: String, default: 'OK' },
  cancelLabel: { type: String, default: 'Cancelar' },
  variant: {
    type: String,
    default: 'primary',
    validator: (v) => ['primary', 'danger'].includes(v),
  },
});

defineEmits(['confirm', 'cancel']);
</script>

<template>
  <BaseModal v-if="open" :title="title" @close="$emit('cancel')">
    <p class="confirm-dialog__message">{{ message }}</p>

    <template #footer>
      <button
        type="button"
        class="form-stack__btn form-stack__btn--secondary"
        @click="$emit('cancel')"
      >
        {{ cancelLabel }}
      </button>
      <button
        type="button"
        class="form-stack__btn"
        :class="variant === 'danger' ? 'form-stack__btn--danger' : 'form-stack__btn--primary'"
        @click="$emit('confirm')"
      >
        {{ confirmLabel }}
      </button>
    </template>
  </BaseModal>
</template>

<style lang="scss" scoped>
@use '../../styles/modals/form-stack';
@use '../../styles/modals/confirm-dialog';
</style>
