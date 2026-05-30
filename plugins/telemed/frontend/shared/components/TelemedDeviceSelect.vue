<script setup>
// Select de dispositivo (câmera, microfone, saída de áudio) usado no
// preflight. Internamente usa FormSelect (popup customizado teleportado pro
// body) — assim o dropdown não fica preso ao estilo nativo feio do OS quando
// abre. API externa preservada: recebe MediaDeviceInfo[] e emite o deviceId.
import { computed } from 'vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';

const props = defineProps({
  label: { type: String, required: true },
  modelValue: { type: String, default: '' },
  // Array de MediaDeviceInfo (ou shape compatível: { deviceId, label }).
  options: { type: Array, default: () => [] },
  // Texto mostrado no placeholder quando options está vazio.
  emptyText: { type: String, default: 'Nenhum dispositivo encontrado' },
  // Fallback label quando o device veio sem label (ex.: permissão recusada).
  fallbackLabel: { type: String, default: 'Dispositivo padrão' },
  disabled: { type: Boolean, default: false },
});

defineEmits(['update:modelValue']);

// Converte MediaDeviceInfo[] → formato esperado pelo FormSelect: { value, label }.
// FormSelect identifica seleção via `value` então usamos deviceId como chave.
const formOptions = computed(() =>
  props.options.map(d => ({
    value: d.deviceId,
    label: d.label || props.fallbackLabel,
  }))
);

// Placeholder do FormSelect: quando há ≥1 device, "Selecione" é redundante
// (já vem pré-selecionado); quando está vazio, mostra a mensagem explicativa.
const placeholder = computed(() =>
  props.options.length === 0 ? props.emptyText : 'Selecione'
);

// Desabilita o campo se prop disabled OU se não há opções pra escolher.
const isDisabled = computed(() => props.disabled || props.options.length === 0);
</script>

<template>
  <div class="telemed-device-select">
    <span class="telemed-device-select__label">
      <span class="telemed-device-select__icon">
        <slot name="icon" />
      </span>
      {{ label }}
    </span>
    <FormSelect
      class="telemed-device-select__field"
      :model-value="modelValue"
      :options="formOptions"
      :placeholder="placeholder"
      :disabled="isDisabled"
      auto-searchable
      no-options-text="Nenhum dispositivo encontrado"
      @update:model-value="$emit('update:modelValue', $event)"
    />
  </div>
</template>

<style scoped>
.telemed-device-select {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.telemed-device-select__label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.04em;
  color: #434656;
  text-transform: uppercase;
}

.telemed-device-select__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #64748b;
}

/* Override no trigger do FormSelect pra casar com o visual do preflight:
   superfície surface-bright, cantos de 12px, altura confortável. FormSelect
   tem seu próprio look default; aqui re-aplicamos o tom Klivy. */
.telemed-device-select__field :deep(.ms-trigger) {
  width: 100%;
  height: 48px;
  padding: 0 16px;
  background: #fcf9f8;
  border: 1px solid #e5e7eb;
  border-radius: 12px;
  font-family: inherit;
  font-size: 14px;
  font-weight: 500;
  color: #1c1b1b;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
  transition:
    border-color 120ms ease,
    box-shadow 120ms ease,
    background 120ms ease;
}

.telemed-device-select__field :deep(.ms-trigger:hover:not(:disabled)) {
  border-color: #cbd5e1;
}

.telemed-device-select__field :deep(.ms-trigger:focus-visible) {
  outline: 0;
  border-color: #1552f1;
  box-shadow: 0 0 0 3px rgba(21, 82, 241, 0.12);
}

.telemed-device-select__field :deep(.ms-trigger:disabled) {
  background: #f1f5f9;
  color: #94a3b8;
  cursor: not-allowed;
}

.telemed-device-select__field :deep(.ms-arrow) {
  color: #64748b;
}

.telemed-device-select__field :deep(.ms-placeholder) {
  color: #94a3b8;
}
</style>
