<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseButton from '../components/BaseButton.vue';
import Badge from '../components/Badge.vue';
import EmptyState from '../components/EmptyState.vue';
import IconDocument from '../components/icons/IconDocument.vue';
import IconWallet from '../components/icons/IconWallet.vue';
import { financialApi } from '../api/financial';
import { useFinancialStore } from '../store/financial';
import { formatCurrency, formatDate } from '../utils/format';

const route = useRoute();
const router = useRouter();
const financial = useFinancialStore();

const installment = ref(null);
const loading = ref(true);

const canPayOnline = computed(() => {
  const s = installment.value?.status;
  return s === 'pendente' || s === 'vencido' || s === 'parcial';
});

function onPay() {
  router.push({
    name: 'installment-pay',
    params: { id: installment.value.id },
  });
}

const STATUS_LABELS = {
  pendente: 'A vencer',
  parcial: 'Parcial',
  recebido: 'Pago',
  vencido: 'Vencida',
  estornado: 'Estornado',
  cancelado: 'Cancelado',
  renegociado: 'Renegociado',
};
const STATUS_VARIANTS = {
  pendente: 'primary',
  parcial: 'warning',
  recebido: 'success',
  vencido: 'danger',
  estornado: 'neutral',
  cancelado: 'neutral',
  renegociado: 'neutral',
};
const METHOD_LABELS = {
  dinheiro: 'Dinheiro',
  pix: 'PIX',
  debito: 'Cartão de débito',
  credito: 'Cartão de crédito',
  boleto: 'Boleto',
  transferencia: 'Transferência',
  cheque: 'Cheque',
  multiplas: 'Múltiplos',
  credito_paciente: 'Crédito do paciente',
};

const statusLabel = computed(
  () => STATUS_LABELS[installment.value?.status] || installment.value?.status
);
const badgeVariant = computed(
  () => STATUS_VARIANTS[installment.value?.status] || 'neutral'
);
const methodLabel = computed(
  () =>
    METHOD_LABELS[installment.value?.payment_method] ||
    installment.value?.payment_method
);

onMounted(async () => {
  try {
    installment.value = await financialApi.installment(route.params.id);
  } catch (_) {
    /* fica null */
  } finally {
    loading.value = false;
  }
});

async function onProof() {
  try {
    await financial.openProof(installment.value.id);
  } catch (e) {
    window.alert(e.message);
  }
}
</script>

<template>
  <AppShell>
    <PageHeader title="Detalhes da parcela" back @back="$router.back()" />

    <div v-if="loading" class="pp-inst__loading">Carregando…</div>

    <div v-else-if="installment" class="pp-inst">
      <!-- Hero -->
      <section
        class="pp-inst__hero"
        :class="{
          'pp-inst__hero--overdue': installment.status === 'vencido',
          'pp-inst__hero--paid': installment.status === 'recebido',
        }"
      >
        <div class="pp-inst__hero-label">
          Parcela {{ installment.number }} de {{ installment.total_in_series }}
        </div>
        <div class="pp-inst__hero-amount">
          {{ formatCurrency(installment.amount_cents) }}
        </div>
        <Badge :variant="badgeVariant" size="sm" class="pp-inst__hero-badge">
          {{ statusLabel }}
        </Badge>
      </section>

      <!-- Detalhes -->
      <BaseCard>
        <div class="pp-inst__row">
          <span class="pp-inst__label">Vencimento</span>
          <span class="pp-inst__value">{{
            formatDate(installment.due_date)
          }}</span>
        </div>
        <div class="pp-inst__row">
          <span class="pp-inst__label">Competência</span>
          <span class="pp-inst__value">{{
            formatDate(installment.competence_date)
          }}</span>
        </div>
        <div v-if="installment.received_at" class="pp-inst__row">
          <span class="pp-inst__label">Pago em</span>
          <span class="pp-inst__value">{{
            formatDate(installment.received_at)
          }}</span>
        </div>
        <div v-if="installment.payment_method" class="pp-inst__row">
          <span class="pp-inst__label">Método</span>
          <span class="pp-inst__value">{{ methodLabel }}</span>
        </div>
        <div
          v-if="
            installment.received_amount_cents > 0 &&
            installment.received_amount_cents < installment.amount_cents
          "
          class="pp-inst__row"
        >
          <span class="pp-inst__label">Recebido</span>
          <span class="pp-inst__value">{{
            formatCurrency(installment.received_amount_cents)
          }}</span>
        </div>
        <div v-if="installment.remaining_cents > 0" class="pp-inst__row">
          <span class="pp-inst__label">A pagar</span>
          <span class="pp-inst__value pp-inst__value--strong">{{
            formatCurrency(installment.remaining_cents)
          }}</span>
        </div>
        <div v-if="installment.notes" class="pp-inst__row">
          <span class="pp-inst__label">Observações</span>
          <span class="pp-inst__value">{{ installment.notes }}</span>
        </div>
      </BaseCard>

      <!-- Ações -->
      <BaseButton v-if="canPayOnline" block size="lg" @click="onPay">
        💳 Pagar online
      </BaseButton>

      <BaseButton
        v-if="installment.has_proof"
        :variant="canPayOnline ? 'secondary' : 'primary'"
        block
        size="lg"
        @click="onProof"
      >
        <IconDocument :size="16" /> Ver comprovante
      </BaseButton>

      <p
        v-if="!installment.has_proof && installment.status === 'recebido'"
        class="pp-inst__notice"
      >
        Esta parcela está paga, mas o comprovante ainda não foi anexado.
      </p>
    </div>

    <EmptyState
      v-else
      title="Parcela não encontrada"
      description="Esta parcela pode ter sido removida ou você não tem acesso a ela."
    >
      <template #icon><IconWallet :size="28" /></template>
      <template #action>
        <BaseButton @click="$router.push({ name: 'financial' })">
          Voltar
        </BaseButton>
      </template>
    </EmptyState>
  </AppShell>
</template>

<style scoped>
.pp-inst {
  padding: 16px var(--pp-content-pad-x);
  display: flex;
  flex-direction: column;
  gap: 16px;
}
@media (min-width: 1024px) {
  .pp-inst {
    max-width: 720px;
  }
}
.pp-inst__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}

.pp-inst__hero {
  padding: 24px;
  border-radius: 16px;
  color: #fff;
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 50%, #4338ca 100%);
  text-align: center;
}
.pp-inst__hero--overdue {
  background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%);
}
.pp-inst__hero--paid {
  background: linear-gradient(135deg, #047857 0%, #065f46 100%);
}
.pp-inst__hero-label {
  font-size: 12px;
  font-weight: 600;
  opacity: 0.85;
  text-transform: uppercase;
  letter-spacing: 1px;
}
.pp-inst__hero-amount {
  font-size: 32px;
  font-weight: 800;
  margin: 8px 0 12px;
}
.pp-inst__hero-badge :deep(.pp-badge) {
  background: rgba(255, 255, 255, 0.25) !important;
  color: #fff !important;
  border-color: rgba(255, 255, 255, 0.35) !important;
}

.pp-inst__row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--pp-color-border);
  font-size: 14px;
}
.pp-inst__row:last-child {
  border-bottom: none;
}
.pp-inst__label {
  color: var(--pp-color-text-muted);
  flex-shrink: 0;
}
.pp-inst__value {
  color: var(--pp-color-text);
  font-weight: 600;
  text-align: right;
}
.pp-inst__value--strong {
  font-size: 16px;
  color: #b91c1c;
}

.pp-inst__notice {
  text-align: center;
  font-size: 13px;
  color: var(--pp-color-text-muted);
  padding: 8px 0;
  margin: 0;
}
.pp-inst__notice--warn {
  color: #b91c1c;
}
</style>
