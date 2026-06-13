<script setup>
// Diálogo de entrada de texto (substitui window.prompt). Usa o BaseModal.
// Enter confirma, Esc/backdrop cancela. Resolve null no cancelamento.

import { ref, watch, nextTick } from 'vue';
import BaseModal from './BaseModal.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  value: { type: String, default: '' },
  confirmLabel: { type: String, default: 'OK' },
  cancelLabel: { type: String, default: 'Cancelar' },
  inputType: { type: String, default: 'text' },
});

const emit = defineEmits(['submit', 'cancel']);

const local = ref(props.value);
const inputRef = ref(null);

// Sincroniza o valor inicial e foca o input quando abre.
watch(
  () => props.open,
  async (isOpen) => {
    if (!isOpen) return;
    local.value = props.value || '';
    await nextTick();
    inputRef.value?.focus();
    inputRef.value?.select();
  },
  { immediate: true },
);

const submit = () => emit('submit', local.value.trim());
</script>

<template>
  <BaseModal v-if="open" :title="title" @close="$emit('cancel')">
    <div class="form-stack">
      <div class="form-stack__field form-stack__field--full">
        <label v-if="label" class="form-stack__label" for="prompt-input">
          {{ label }}
        </label>
        <input
          id="prompt-input"
          ref="inputRef"
          v-model="local"
          :type="inputType"
          :placeholder="placeholder"
          class="form-stack__input reset-base"
          @keydown.enter.prevent="submit"
        />
      </div>
    </div>

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
        class="form-stack__btn form-stack__btn--primary"
        @click="submit"
      >
        {{ confirmLabel }}
      </button>
    </template>
  </BaseModal>
</template>

<style lang="scss" scoped>
@use '../../styles/modals/form-stack';
</style>
