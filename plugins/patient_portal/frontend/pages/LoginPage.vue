<template>
  <AuthLayout
    title="Entrar no Portal do Paciente"
    subtitle="Digite seu e-mail ou telefone para receber um código de acesso."
  >
    <form @submit.prevent="onSubmit" class="pp-login">
      <BaseInput
        v-model="identifier"
        label="E-mail ou telefone"
        placeholder="seu@email.com ou (11) 99999-9999"
        autocomplete="email"
        :error="auth.error"
      />

      <div class="pp-login__channels">
        <label class="pp-login__channel">
          <input v-model="channel" type="radio" value="email" />
          <span>Receber por e-mail</span>
        </label>
        <label class="pp-login__channel pp-login__channel--disabled" title="WhatsApp será habilitado em breve">
          <input v-model="channel" type="radio" value="whatsapp" disabled />
          <span>Receber por WhatsApp <em>(em breve)</em></span>
        </label>
      </div>

      <BaseButton type="submit" :loading="auth.loading" block>
        Enviar código
      </BaseButton>
    </form>
  </AuthLayout>
</template>

<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../store/auth';
import AuthLayout from '../components/AuthLayout.vue';
import BaseInput from '../components/BaseInput.vue';
import BaseButton from '../components/BaseButton.vue';

const auth = useAuthStore();
const router = useRouter();

const identifier = ref('');
const channel = ref('email');

async function onSubmit() {
  auth.clearError();
  try {
    await auth.requestOtp({ identifier: identifier.value.trim(), channel: channel.value });
    router.push({ name: 'verify' });
  } catch (_) { /* erro já vai pro store */ }
}
</script>

<style scoped>
.pp-login { display: flex; flex-direction: column; gap: 20px; }
.pp-login__channels {
  display: flex; flex-direction: column; gap: 8px;
  padding: 12px; border: 1px dashed var(--pp-color-border); border-radius: 10px;
}
.pp-login__channel {
  display: flex; align-items: center; gap: 8px; font-size: 14px; color: var(--pp-color-text);
  cursor: pointer;
}
.pp-login__channel--disabled { color: var(--pp-color-text-muted); cursor: not-allowed; }
.pp-login__channel--disabled em { font-style: normal; font-size: 12px; }
</style>
