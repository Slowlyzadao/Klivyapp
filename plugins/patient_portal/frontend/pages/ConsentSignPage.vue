<template>
  <AppShell>
    <PageHeader title="Termo de consentimento" back @back="$router.back()" />

    <div v-if="loading" class="pp-consent-sign__loading">Carregando…</div>

    <div v-else-if="consent" class="pp-consent-sign">
      <!-- Hero -->
      <section class="pp-consent-sign__hero">
        <div class="pp-consent-sign__hero-icon"><IconShield :size="22" /></div>
        <h2 class="pp-consent-sign__hero-title">{{ consent.title }}</h2>
        <Badge :variant="consent.status === 'signed' ? 'success' : 'warning'" size="sm">
          {{ consent.status === 'signed' ? 'Assinado' : 'Aguardando assinatura' }}
        </Badge>
      </section>

      <!-- Corpo do termo -->
      <BaseCard title="Conteúdo do termo">
        <p class="pp-consent-sign__body">{{ consent.body || 'Termo sem conteúdo descritivo.' }}</p>
        <p v-if="consent.observations" class="pp-consent-sign__obs">
          <strong>Observações:</strong> {{ consent.observations }}
        </p>
      </BaseCard>

      <!-- Assinatura: se pendente, abre o pad. Se já assinado, mostra confirmação. -->
      <BaseCard v-if="consent.can_sign" title="Sua assinatura">
        <SignaturePad ref="padRef" @update:dataUrl="onSignatureChange" />

        <label class="pp-consent-sign__agree">
          <input type="checkbox" v-model="agreed" />
          <span>Li o termo acima e concordo com seu conteúdo.</span>
        </label>

        <p v-if="error" class="pp-consent-sign__error">{{ error }}</p>

        <BaseButton
          block size="lg"
          :loading="submitting"
          :disabled="!canSubmit"
          @click="onSign"
        >
          <IconCheck :size="16" /> Confirmar e assinar
        </BaseButton>
      </BaseCard>

      <BaseCard v-else-if="consent.status === 'signed'">
        <div class="pp-consent-sign__done">
          <div class="pp-consent-sign__done-icon"><IconCheck :size="32" /></div>
          <div>
            <div class="pp-consent-sign__done-title">Termo assinado</div>
            <div class="pp-consent-sign__done-meta">
              Em {{ formatDateTime(consent.signed_at) }} · canal: {{ consent.signature_method === 'remote' ? 'portal do paciente' : 'tablet local' }}
            </div>
          </div>
        </div>
      </BaseCard>

      <p v-if="consent.expires_at && consent.status !== 'signed'" class="pp-consent-sign__expires">
        Válido até {{ formatDate(consent.expires_at) }}.
      </p>
    </div>

    <EmptyState
      v-else
      title="Termo não encontrado"
      description="Este termo pode ter sido removido ou você não tem acesso."
    >
      <template #icon><IconShield :size="28" /></template>
      <template #action>
        <BaseButton @click="$router.push({ name: 'consent-records' })">Voltar</BaseButton>
      </template>
    </EmptyState>
  </AppShell>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseButton from '../components/BaseButton.vue';
import Badge from '../components/Badge.vue';
import EmptyState from '../components/EmptyState.vue';
import SignaturePad from '../components/SignaturePad.vue';
import IconShield from '../components/icons/IconShield.vue';
import IconCheck from '../components/icons/IconCheck.vue';
import { consentRecordsApi } from '../api/consent_records';
import { useConsentRecordsStore } from '../store/consent_records';
import { formatDate, formatDateTime } from '../utils/format';

const route  = useRoute();
const router = useRouter();
const store  = useConsentRecordsStore();

const consent      = ref(null);
const loading      = ref(true);
const submitting   = ref(false);
const error        = ref(null);
const signatureUrl = ref(null);
const agreed       = ref(false);
const padRef       = ref(null);

const canSubmit = computed(() => agreed.value && !!signatureUrl.value);

onMounted(async () => {
  try {
    consent.value = await consentRecordsApi.get(route.params.id);
  } catch (_) { /* fica null */ }
  finally { loading.value = false; }
});

function onSignatureChange(url) { signatureUrl.value = url; }

async function onSign() {
  error.value = null;
  submitting.value = true;
  try {
    const updated = await store.sign(consent.value.id, signatureUrl.value);
    consent.value = updated;
    setTimeout(() => router.push({ name: 'consent-records' }), 800);
  } catch (e) {
    error.value = e.message;
  } finally {
    submitting.value = false;
  }
}
</script>

<style scoped>
.pp-consent-sign { padding: 16px; display: flex; flex-direction: column; gap: 16px; }
.pp-consent-sign__loading { padding: 32px; text-align: center; color: var(--pp-color-text-muted); font-size: 14px; }

.pp-consent-sign__hero {
  display: flex; flex-direction: column; align-items: flex-start; gap: 12px;
  padding: 20px; border-radius: 16px;
  background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%);
  border: 1px solid #fcd34d;
}
.pp-consent-sign__hero-icon {
  width: 40px; height: 40px; border-radius: 12px;
  display: flex; align-items: center; justify-content: center;
  background: #fff; color: #92400e;
}
.pp-consent-sign__hero-title { margin: 0; font-size: 18px; font-weight: 700; color: #78350f; }

.pp-consent-sign__body { margin: 0; font-size: 14px; line-height: 1.6; color: var(--pp-color-text); white-space: pre-wrap; }
.pp-consent-sign__obs  { margin: 12px 0 0; font-size: 13px; color: var(--pp-color-text-muted); }

.pp-consent-sign__agree {
  display: flex; align-items: flex-start; gap: 10px;
  margin: 16px 0;
  font-size: 13px; color: var(--pp-color-text);
}
.pp-consent-sign__agree input[type=checkbox] { margin-top: 2px; flex-shrink: 0; }

.pp-consent-sign__error { color: #b91c1c; font-size: 13px; margin: 0 0 12px; }
.pp-consent-sign__expires { text-align: center; font-size: 12px; color: var(--pp-color-text-muted); margin: 0; }

.pp-consent-sign__done { display: flex; align-items: center; gap: 14px; }
.pp-consent-sign__done-icon {
  width: 56px; height: 56px; border-radius: 16px;
  display: flex; align-items: center; justify-content: center;
  background: #d1fae5; color: #047857; flex-shrink: 0;
}
.pp-consent-sign__done-title { font-size: 16px; font-weight: 700; color: var(--pp-color-text); }
.pp-consent-sign__done-meta  { font-size: 13px; color: var(--pp-color-text-muted); margin-top: 2px; }
</style>
