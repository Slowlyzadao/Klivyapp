<template>
  <div class="pp-consent">
    <div class="pp-consent__card">
      <header class="pp-consent__header">
        <div class="pp-consent__icon"><IconShield :size="28" /></div>
        <h1 class="pp-consent__title">Termo de uso e privacidade</h1>
        <p class="pp-consent__subtitle">
          Antes de continuar, leia e aceite os termos do Portal do Paciente.
        </p>
      </header>

      <article class="pp-consent__terms" ref="termsRef" @scroll="onScroll">
        <h2>1. Sobre o Portal do Paciente</h2>
        <p>
          O Portal do Paciente Klivy é uma extensão da plataforma da sua clínica
          que permite acompanhar consultas, situação financeira, documentos e
          comunicação direta com a equipe.
        </p>

        <h2>2. Tratamento de dados (LGPD)</h2>
        <p>
          Seus dados pessoais e clínicos são tratados pela clínica responsável
          pelo seu atendimento, conforme a Lei Geral de Proteção de Dados
          (Lei 13.709/2018). A Klivy atua como operadora dos dados em nome da
          clínica e segue as melhores práticas de segurança.
        </p>

        <h2>3. Acessos e responsabilidades</h2>
        <ul>
          <li>O acesso é pessoal e intransferível.</li>
          <li>Cada login dispara um código de verificação único (OTP).</li>
          <li>Todos os acessos são registrados em trilha de auditoria.</li>
        </ul>

        <h2>4. Direitos do titular</h2>
        <p>
          Você pode, a qualquer momento, exportar seus dados, solicitar
          correção ou pedir a exclusão pela aba <em>Mais → Privacidade</em>.
          A solicitação de exclusão converte seus dados em registros
          anonimizados (o prontuário precisa ser preservado por 20 anos
          conforme exigência do CFM).
        </p>

        <h2>5. Comunicação</h2>
        <p>
          Você pode receber notificações por e-mail e WhatsApp sobre
          confirmações, lembretes e novidades da clínica. As preferências
          são ajustáveis em <em>Mais → Notificações</em>.
        </p>

        <h2>6. Versão do termo</h2>
        <p>v{{ auth.consent.term_version || '1.0' }} — efetivo a partir de maio de 2026.</p>
      </article>

      <label class="pp-consent__accept" :class="{ 'pp-consent__accept--locked': !readEnough }">
        <input type="checkbox" v-model="accepted" :disabled="!readEnough" />
        <span>
          Li e aceito os termos acima.
          <span v-if="!readEnough" class="pp-consent__accept-hint">(role até o fim para habilitar)</span>
        </span>
      </label>

      <div class="pp-consent__actions">
        <BaseButton variant="secondary" @click="onLogout">Sair</BaseButton>
        <BaseButton :disabled="!accepted" :loading="loading" @click="onAccept" block>
          Aceitar e continuar
        </BaseButton>
      </div>

      <p v-if="error" class="pp-consent__error">{{ error }}</p>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../store/auth';
import BaseButton from '../components/BaseButton.vue';
import IconShield from '../components/icons/IconShield.vue';

const auth = useAuthStore();
const router = useRouter();

const termsRef  = ref(null);
const readEnough = ref(false);
const accepted   = ref(false);
const loading    = ref(false);
const error      = ref(null);

function onScroll(e) {
  const el = e.target;
  if (el.scrollHeight - el.scrollTop - el.clientHeight < 40) readEnough.value = true;
}

async function onAccept() {
  loading.value = true; error.value = null;
  try {
    await auth.acceptPortalTerms();
    router.replace({ name: 'home' });
  } catch (e) {
    error.value = e.message;
  } finally { loading.value = false; }
}

async function onLogout() {
  await auth.logout();
  router.replace({ name: 'login' });
}
</script>

<style scoped>
.pp-consent {
  min-height: 100vh;
  display: flex; align-items: center; justify-content: center;
  padding: 24px;
  background: linear-gradient(180deg, #f8fafc 0%, #eef2ff 100%);
}
.pp-consent__card {
  width: 100%; max-width: 520px;
  background: #fff; border: 1px solid var(--pp-color-border);
  border-radius: 24px; padding: 28px;
  box-shadow: 0 12px 40px rgba(15,23,42,.08);
  display: flex; flex-direction: column; gap: 20px;
  max-height: calc(100vh - 48px);
}
.pp-consent__header { text-align: center; display: flex; flex-direction: column; align-items: center; gap: 8px; }
.pp-consent__icon {
  width: 56px; height: 56px; border-radius: 16px;
  display: flex; align-items: center; justify-content: center;
  background: rgba(37, 99, 235, .1); color: var(--pp-color-primary);
}
.pp-consent__title    { margin: 4px 0 0; font-size: 20px; font-weight: 700; color: var(--pp-color-text); }
.pp-consent__subtitle { margin: 0; font-size: 14px; color: var(--pp-color-text-muted); }

.pp-consent__terms {
  overflow-y: auto;
  background: #f8fafc;
  border: 1px solid var(--pp-color-border);
  border-radius: 14px;
  padding: 16px 18px;
  font-size: 14px; line-height: 1.55;
  color: #334155;
  max-height: 320px;
}
.pp-consent__terms h2 { font-size: 14px; font-weight: 700; color: var(--pp-color-text); margin: 18px 0 6px; }
.pp-consent__terms h2:first-child { margin-top: 0; }
.pp-consent__terms p, .pp-consent__terms ul { margin: 0 0 8px; }
.pp-consent__terms ul { padding-left: 18px; }
.pp-consent__terms em { font-style: normal; font-weight: 600; color: var(--pp-color-primary); }

.pp-consent__accept {
  display: flex; align-items: flex-start; gap: 10px;
  font-size: 14px; color: var(--pp-color-text);
  cursor: pointer; user-select: none;
}
.pp-consent__accept input { margin-top: 3px; }
.pp-consent__accept--locked { color: var(--pp-color-text-muted); cursor: not-allowed; }
.pp-consent__accept-hint    { font-size: 12px; color: var(--pp-color-text-muted); margin-left: 4px; }

.pp-consent__actions { display: grid; grid-template-columns: auto 1fr; gap: 10px; }
.pp-consent__error { margin: 0; color: #dc2626; font-size: 13px; text-align: center; }
</style>
