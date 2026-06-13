<template>
  <div class="pp-otp" :class="{ 'pp-otp--error': !!error }">
    <input
      v-for="(_, i) in length"
      :key="i"
      :ref="el => (inputs[i] = el)"
      v-model="digits[i]"
      type="text"
      inputmode="numeric"
      maxlength="1"
      autocomplete="one-time-code"
      class="pp-otp__digit"
      @input="onInput(i, $event)"
      @keydown="onKeydown(i, $event)"
      @paste="onPaste"
    />
  </div>
  <p v-if="error" class="pp-otp__error">{{ error }}</p>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  length:     { type: Number, default: 6 },
  error:      String
});
const emit = defineEmits(['update:modelValue', 'complete']);

const digits = ref(Array(props.length).fill(''));
const inputs = ref([]);

onMounted(() => { inputs.value[0]?.focus(); });

watch(() => props.modelValue, (v) => {
  // Permite reset externo (ex: limpar quando OTP errado)
  if (v === '' && digits.value.some(Boolean)) digits.value = Array(props.length).fill('');
});

function emitValue() {
  const joined = digits.value.join('');
  emit('update:modelValue', joined);
  if (joined.length === props.length && /^\d+$/.test(joined)) emit('complete', joined);
}

function onInput(i, e) {
  const raw = e.target.value.replace(/\D/g, '');
  digits.value[i] = raw.slice(0, 1);
  if (raw && i < props.length - 1) inputs.value[i + 1]?.focus();
  emitValue();
}

function onKeydown(i, e) {
  if (e.key === 'Backspace' && !digits.value[i] && i > 0) inputs.value[i - 1]?.focus();
}

function onPaste(e) {
  const text = (e.clipboardData?.getData('text') || '').replace(/\D/g, '').slice(0, props.length);
  if (!text) return;
  e.preventDefault();
  for (let i = 0; i < props.length; i++) digits.value[i] = text[i] || '';
  inputs.value[Math.min(text.length, props.length - 1)]?.focus();
  emitValue();
}
</script>

<style scoped>
.pp-otp { display: flex; gap: 8px; justify-content: center; }
.pp-otp__digit {
  width: 48px; height: 56px; text-align: center;
  font-size: 24px; font-weight: 700;
  border: 1px solid var(--pp-color-border); border-radius: 10px;
  background: #fff; color: var(--pp-color-text);
  transition: border 120ms ease, box-shadow 120ms ease;
}
.pp-otp__digit:focus {
  outline: none; border-color: var(--pp-color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, .12);
}
.pp-otp--error .pp-otp__digit { border-color: #dc2626; }
.pp-otp__error { margin: 8px 0 0; font-size: 12px; color: #dc2626; text-align: center; }
</style>
