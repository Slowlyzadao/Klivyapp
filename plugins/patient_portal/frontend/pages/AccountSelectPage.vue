<template>
  <AuthLayout
    title="Em qual clínica você quer entrar?"
    subtitle="Encontramos seu cadastro em mais de uma clínica."
  >
    <div class="pp-select">
      <button
        v-for="acc in auth.accounts"
        :key="acc.account_id"
        type="button"
        class="pp-select__item"
        :disabled="auth.loading"
        @click="onSelect(acc.account_id)"
      >
        <div class="pp-select__avatar">{{ initials(acc.account_name) }}</div>
        <div class="pp-select__meta">
          <div class="pp-select__name">{{ acc.account_name }}</div>
          <div class="pp-select__patient">{{ acc.patient_name }}</div>
        </div>
        <div class="pp-select__chevron">›</div>
      </button>

      <p v-if="auth.error" class="pp-select__error">{{ auth.error }}</p>
    </div>
  </AuthLayout>
</template>

<script setup>
import { onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../store/auth';
import AuthLayout from '../components/AuthLayout.vue';

const auth = useAuthStore();
const router = useRouter();

onMounted(() => {
  if (!auth.tempToken || auth.accounts.length === 0) router.replace({ name: 'login' });
});

async function onSelect(accountId) {
  await auth.selectAccount(accountId);
  if (auth.isAuthenticated) router.push({ name: 'home' });
}

function initials(name) {
  if (!name) return '?';
  return name.split(/\s+/).slice(0, 2).map(s => s[0]?.toUpperCase()).join('');
}
</script>

<style scoped>
.pp-select { display: flex; flex-direction: column; gap: 12px; }
.pp-select__item {
  display: flex; align-items: center; gap: 12px;
  padding: 14px 16px; border: 1px solid var(--pp-color-border); border-radius: 12px;
  background: #fff; cursor: pointer; text-align: left;
  transition: border 120ms ease, transform 80ms ease;
}
.pp-select__item:hover:not(:disabled) { border-color: var(--pp-color-primary); }
.pp-select__item:active:not(:disabled) { transform: translateY(1px); }
.pp-select__item:disabled { opacity: .6; cursor: not-allowed; }
.pp-select__avatar {
  width: 40px; height: 40px; border-radius: 50%;
  background: var(--pp-color-primary); color: #fff;
  display: flex; align-items: center; justify-content: center;
  font-size: 13px; font-weight: 700;
}
.pp-select__meta { flex: 1; min-width: 0; }
.pp-select__name { font-size: 15px; font-weight: 600; color: var(--pp-color-text); }
.pp-select__patient { font-size: 12px; color: var(--pp-color-text-muted); margin-top: 2px; }
.pp-select__chevron { font-size: 28px; color: var(--pp-color-text-muted); line-height: 1; }
.pp-select__error { margin-top: 12px; font-size: 13px; color: #dc2626; text-align: center; }
</style>
