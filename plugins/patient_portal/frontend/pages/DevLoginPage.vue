<template>
  <div class="pp-devlogin">
    <p>Logando…</p>
  </div>
</template>

<script setup>
// Dev-only — entra direto com JWT via querystring.
// Uso: /dev_login?token=eyJ...&next=/appointments/76/telemed
//
// Seta o JWT no localStorage e força reload completo pra que o auth store
// hidrate do zero. Sem essa rota o teste de telemedicina exigia OTP +
// letter_opener — atrito desnecessário pra desenvolvimento.
//
// AUDIT 2026-05-25: Gate de ambiente OBRIGATÓRIO. Sem isso, qualquer
// visitante em prod com `/dev_login?token=eyJ...&next=...` sobrescrevia o
// JWT no localStorage (session-fixation via phishing). Vite expõe
// `import.meta.env.DEV` que é `true` só em dev server / `false` em build
// de prod — checagem client-side somada à exclusão da rota em prod (router)
// dá defesa em profundidade.
import { onMounted } from 'vue';

onMounted(() => {
  if (!import.meta.env.DEV) {
    window.location.replace('/login');
    return;
  }

  const params = new URLSearchParams(window.location.search);
  const token = params.get('token');
  const next  = params.get('next') || '/';

  if (token) {
    localStorage.setItem('pp.jwt', token);
  }
  window.location.replace(next);
});
</script>

<style scoped>
.pp-devlogin {
  display: flex; align-items: center; justify-content: center;
  height: 100vh; font-size: 14px; color: var(--pp-color-text-muted);
}
</style>
