<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseButton from '../components/BaseButton.vue';
import PaymentMethodCard from '../components/PaymentMethodCard.vue';
import QrCanvas from '../components/QrCanvas.vue';
import IconWallet from '../components/icons/IconWallet.vue';
import IconDocument from '../components/icons/IconDocument.vue';
import IconCheck from '../components/icons/IconCheck.vue';
import { financialApi } from '../api/financial';
import { usePaymentsStore } from '../store/payments';
import { formatCurrency, formatDate } from '../utils/format';

const route = useRoute();
const router = useRouter();
const payments = usePaymentsStore();

const ERROR_LABELS = {
  expired: 'Pagamento expirado',
  failed: 'Não foi possível processar',
  cancelled: 'Pagamento cancelado',
};

const installment = ref(null);
const installmentLoading = ref(true);
const copied = ref(false);
const countdownTimer = ref(null);
const countdown = ref('--:--');
const installmentId = computed(() => Number(route.params.id));

const current = computed(() => payments.current);
const loading = computed(() => payments.loading);

const title = computed(() => {
  if (!current.value) return 'Pagar parcela';
  if (current.value.status === 'paid') return 'Pago';
  return 'Pagamento';
});

onMounted(async () => {
  try {
    installment.value = await financialApi.installment(installmentId.value);
  } catch (_) {
    /* fica null */
  } finally {
    installmentLoading.value = false;
  }
});

onBeforeUnmount(() => {
  payments.stopPolling();
  if (countdownTimer.value) clearInterval(countdownTimer.value);
});

async function startPayment(method) {
  await payments.start({ installmentId: installmentId.value, method });
  if (current.value?.status === 'awaiting_payment') {
    payments.startPolling(current.value.id);
    startCountdown();
  }
}

function startCountdown() {
  if (countdownTimer.value) clearInterval(countdownTimer.value);
  const update = () => {
    if (!current.value?.expires_at) {
      countdown.value = '--:--';
      return;
    }
    const ms = new Date(current.value.expires_at) - new Date();
    if (ms <= 0) {
      countdown.value = 'expirado';
      clearInterval(countdownTimer.value);
      return;
    }
    const mins = Math.floor(ms / 60000);
    const secs = Math.floor((ms % 60000) / 1000);
    countdown.value = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  };
  update();
  countdownTimer.value = setInterval(update, 1000);
}

async function copyPix() {
  await navigator.clipboard.writeText(current.value.pix_copy_paste);
  copied.value = true;
  setTimeout(() => {
    copied.value = false;
  }, 2000);
}

async function copyBoleto() {
  await navigator.clipboard.writeText(current.value.boleto_barcode);
  copied.value = true;
  setTimeout(() => {
    copied.value = false;
  }, 2000);
}

async function onCancel() {
  if (!window.confirm('Tem certeza que quer cancelar este pagamento?')) return;
  await payments.cancel(current.value.id);
}

async function onSimulate() {
  await payments.simulatePaid(current.value.id);
}

function resetAndChooseAgain() {
  payments.reset();
}

function onBack() {
  if (current.value?.status === 'awaiting_payment') {
    if (!window.confirm('Você tem um pagamento em andamento. Sair?')) return;
  }
  router.back();
}
</script>

<template>
  <AppShell>
    <PageHeader :title="title" back @back="onBack" />

    <div v-if="loading || installmentLoading" class="pp-pay__loading">
      Carregando…
    </div>

    <div v-else class="pp-pay">
      <!-- Resumo da parcela -->
      <section v-if="installment" class="pp-pay__summary">
        <div class="pp-pay__summary-label">Você está pagando</div>
        <div class="pp-pay__summary-amount">
          {{ formatCurrency(installment.amount_cents) }}
        </div>
        <div class="pp-pay__summary-meta">
          Parcela {{ installment.number }}/{{ installment.total_in_series }} ·
          vence {{ formatDate(installment.due_date) }}
        </div>
      </section>

      <!-- Estado: escolha de método -->
      <section v-if="!current" class="pp-pay__methods">
        <h3 class="pp-pay__section-title">Como quer pagar?</h3>
        <PaymentMethodCard
          label="PIX"
          hint="Pagamento instantâneo · QR code"
          :icon="IconWallet"
          color="#10b981"
          @click="startPayment('pix')"
        />
        <PaymentMethodCard
          label="Boleto"
          hint="Pague em qualquer banco · até 3 dias úteis"
          :icon="IconDocument"
          color="#f59e0b"
          @click="startPayment('boleto')"
        />
        <PaymentMethodCard
          label="Cartão"
          hint="Em breve"
          :icon="IconWallet"
          color="#8b5cf6"
          disabled
        />
      </section>

      <!-- Estado: PIX awaiting -->
      <section
        v-else-if="
          current.status === 'awaiting_payment' && current.method === 'pix'
        "
        class="pp-pay__pix"
      >
        <div class="pp-pay__pix-qr-wrap">
          <QrCanvas :value="current.pix_copy_paste" :size="256" />
        </div>
        <p class="pp-pay__pix-info">
          Abra o app do seu banco, escolha PIX → Pagar com QR Code, e aponte
          para a imagem.
        </p>

        <div class="pp-pay__copy-row">
          <input
            ref="copyInput"
            :value="current.pix_copy_paste"
            readonly
            class="pp-pay__copy-input"
          />
          <button type="button" class="pp-pay__copy-btn" @click="copyPix">
            {{ copied ? 'Copiado ✓' : 'Copiar' }}
          </button>
        </div>

        <div v-if="current.expires_at" class="pp-pay__countdown">
          Expira em <strong>{{ countdown }}</strong>
        </div>

        <div class="pp-pay__waiting">
          <span class="pp-pay__spinner" />
          Aguardando confirmação…
        </div>

        <BaseButton
          v-if="current.can_simulate"
          variant="secondary"
          block
          @click="onSimulate"
        >
          🧪 Simular pagamento (DEV)
        </BaseButton>

        <BaseButton variant="ghost-danger" block @click="onCancel">
          Cancelar
        </BaseButton>
      </section>

      <!-- Estado: Boleto awaiting -->
      <section
        v-else-if="
          current.status === 'awaiting_payment' && current.method === 'boleto'
        "
        class="pp-pay__boleto"
      >
        <div class="pp-pay__boleto-icon"><IconDocument :size="40" /></div>
        <p class="pp-pay__boleto-info">
          Sua linha digitável está pronta. Cole no app do banco para pagar.
        </p>

        <div class="pp-pay__copy-row">
          <input
            :value="current.boleto_barcode"
            readonly
            class="pp-pay__copy-input pp-pay__copy-input--mono"
          />
          <button type="button" class="pp-pay__copy-btn" @click="copyBoleto">
            {{ copied ? 'Copiado ✓' : 'Copiar' }}
          </button>
        </div>

        <a
          v-if="current.boleto_url"
          :href="current.boleto_url"
          target="_blank"
          class="pp-pay__boleto-link"
        >
          📄 Abrir boleto em PDF
        </a>

        <div class="pp-pay__waiting">
          <span class="pp-pay__spinner" />
          Aguardando compensação bancária…
        </div>

        <BaseButton
          v-if="current.can_simulate"
          variant="secondary"
          block
          @click="onSimulate"
        >
          🧪 Simular pagamento (DEV)
        </BaseButton>

        <BaseButton variant="ghost-danger" block @click="onCancel">
          Cancelar
        </BaseButton>
      </section>

      <!-- Estado: pago -->
      <section v-else-if="current.status === 'paid'" class="pp-pay__success">
        <div class="pp-pay__success-icon"><IconCheck :size="40" /></div>
        <h2 class="pp-pay__success-title">Pagamento confirmado</h2>
        <p class="pp-pay__success-text">
          Recibo gerado automaticamente — disponível em
          <strong>Saúde → Documentos</strong>.
        </p>
        <BaseButton
          block
          size="lg"
          @click="$router.push({ name: 'financial' })"
        >
          Voltar ao financeiro
        </BaseButton>
        <BaseButton
          variant="ghost"
          block
          @click="$router.push({ name: 'health' })"
        >
          Ver recibo
        </BaseButton>
      </section>

      <!-- Estados de erro -->
      <section
        v-else-if="['expired', 'failed', 'cancelled'].includes(current.status)"
        class="pp-pay__error"
      >
        <h2 class="pp-pay__error-title">{{ ERROR_LABELS[current.status] }}</h2>
        <p class="pp-pay__error-text">Você pode iniciar uma nova tentativa.</p>
        <BaseButton block @click="resetAndChooseAgain">
          Tentar de novo
        </BaseButton>
      </section>
    </div>
  </AppShell>
</template>

<style scoped>
.pp-pay {
  padding: 16px var(--pp-content-pad-x);
  display: flex;
  flex-direction: column;
  gap: 20px;
}
@media (min-width: 1024px) {
  .pp-pay {
    max-width: 680px;
  }
}
.pp-pay__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}

.pp-pay__summary {
  padding: 20px;
  border-radius: 16px;
  text-align: center;
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 50%, #4338ca 100%);
  color: #fff;
}
.pp-pay__summary-label {
  font-size: 12px;
  font-weight: 600;
  opacity: 0.85;
  text-transform: uppercase;
  letter-spacing: 1px;
}
.pp-pay__summary-amount {
  font-size: 32px;
  font-weight: 800;
  margin: 6px 0 4px;
}
.pp-pay__summary-meta {
  font-size: 13px;
  opacity: 0.92;
}

.pp-pay__section-title {
  margin: 0 0 10px;
  font-size: 13px;
  font-weight: 700;
  color: var(--pp-color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
.pp-pay__methods {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.pp-pay__pix,
.pp-pay__boleto {
  display: flex;
  flex-direction: column;
  gap: 12px;
  align-items: stretch;
}
.pp-pay__pix-qr-wrap {
  display: flex;
  justify-content: center;
  padding: 16px;
  background: #fff;
  border: 1px solid var(--pp-color-border);
  border-radius: 16px;
}
.pp-pay__pix-info,
.pp-pay__boleto-info {
  margin: 0;
  font-size: 14px;
  color: var(--pp-color-text-muted);
  text-align: center;
}

.pp-pay__copy-row {
  display: flex;
  gap: 8px;
}
.pp-pay__copy-input {
  flex: 1;
  padding: 10px 12px;
  border-radius: 10px;
  border: 1px solid var(--pp-color-border);
  font-size: 13px;
  font-family: inherit;
  background: #f8fafc;
  min-width: 0;
}
.pp-pay__copy-input--mono {
  font-family:
    ui-monospace,
    SF Mono,
    monospace;
  font-size: 12px;
}
.pp-pay__copy-btn {
  background: var(--pp-color-primary);
  color: #fff;
  padding: 10px 16px;
  border-radius: 10px;
  border: none;
  font-size: 13px;
  font-weight: 700;
  cursor: pointer;
  white-space: nowrap;
}

.pp-pay__countdown {
  text-align: center;
  font-size: 13px;
  color: var(--pp-color-text-muted);
}
.pp-pay__waiting {
  display: inline-flex;
  gap: 8px;
  align-items: center;
  justify-content: center;
  padding: 12px;
  color: var(--pp-color-text-muted);
  font-size: 13px;
}
.pp-pay__spinner {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  border: 2px solid currentColor;
  border-top-color: transparent;
  animation: pp-pay-spin 0.8s linear infinite;
}
@keyframes pp-pay-spin {
  to {
    transform: rotate(360deg);
  }
}

.pp-pay__boleto-icon {
  display: flex;
  justify-content: center;
  padding: 16px;
  color: var(--pp-color-primary);
}
.pp-pay__boleto-link {
  text-align: center;
  padding: 12px;
  background: #f1f5f9;
  border-radius: 10px;
  text-decoration: none;
  font-weight: 600;
  color: var(--pp-color-text);
  font-size: 14px;
}

.pp-pay__success {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 24px;
  background: linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%);
  border: 1px solid #6ee7b7;
  border-radius: 16px;
}
.pp-pay__success-icon {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  background: #fff;
  color: #047857;
  display: flex;
  align-items: center;
  justify-content: center;
}
.pp-pay__success-title {
  margin: 0;
  font-size: 22px;
  font-weight: 800;
  color: #065f46;
}
.pp-pay__success-text {
  margin: 0 0 8px;
  text-align: center;
  color: #065f46;
  font-size: 14px;
}

.pp-pay__error {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 24px;
  background: #fef2f2;
  border: 1px solid #fecaca;
  border-radius: 16px;
}
.pp-pay__error-title {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
  color: #b91c1c;
}
.pp-pay__error-text {
  margin: 0 0 8px;
  font-size: 14px;
  color: #7f1d1d;
}
</style>
