<template>
  <AuthLayout
    title="Confirme seu código"
    :subtitle="`Enviamos um código de 6 dígitos para ${maskedIdentifier}.`"
  >
    <form @submit.prevent="onSubmit" class="pp-verify">
      <OtpInput v-model="code" :error="auth.error" @complete="onSubmit" />

      <BaseButton type="submit" :loading="auth.loading" :disabled="code.length !== 6" block>
        Confirmar
      </BaseButton>

      <button class="pp-verify__back" type="button" @click="goBack">Trocar e-mail/telefone</button>
    </form>
  </AuthLayout>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../store/auth';
import AuthLayout from '../components/AuthLayout.vue';
import OtpInput from '../components/OtpInput.vue';
import BaseButton from '../components/BaseButton.vue';

const auth = useAuthStore();
const router = useRouter();
const code = ref('');

onMounted(() => {
  // Veio direto pra essa rota sem ter pedido OTP? Volta pro login.
  if (!auth.identifier) router.replace({ name: 'login' });
});

const maskedIdentifier = computed(() => {
  const v = auth.identifier;
  if (!v) return '';
  if (v.includes('@')) {
    const [user, domain] = v.split('@');
    return `${user.slice(0, 2)}***@${domain}`;
  }
  return v.replace(/(\+?\d{2})(\d+)(\d{2})/, (_, a, b, c) => `${a}${'*'.repeat(b.length)}${c}`);
});

async function onSubmit() {
  auth.clearError();
  try {
    await auth.verifyOtp({ code: code.value });
    if (auth.isAuthenticated) return router.push({ name: 'home' });
    if (auth.accounts.length > 1) return router.push({ name: 'select-account' });
  } catch (_) { code.value = ''; }
}

function goBack() {
  code.value = '';
  auth.clearError();
  router.push({ name: 'login' });
}
</script>

<style scoped>
.pp-verify { display: flex; flex-direction: column; gap: 20px; }
.pp-verify__back {
  background: none; border: none; cursor: pointer;
  font-size: 13px; color: var(--pp-color-text-muted);
  padding: 8px;
}
.pp-verify__back:hover { color: var(--pp-color-text); }
</style>
