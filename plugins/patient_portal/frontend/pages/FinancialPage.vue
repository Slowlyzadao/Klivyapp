<script setup>
import { ref, computed, onMounted } from 'vue';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import EmptyState from '../components/EmptyState.vue';
import InstallmentCard from '../components/InstallmentCard.vue';
import IconCheck from '../components/icons/IconCheck.vue';
import { useFinancialStore } from '../store/financial';
import { formatCurrency } from '../utils/format';

const financial = useFinancialStore();
const tab = ref('open');

const tabs = computed(() => {
  const list = [
    { key: 'open', label: 'Em aberto' },
    { key: 'all', label: 'Todas' },
  ];
  if (financial.showPaidHistory)
    list.splice(1, 0, { key: 'paid', label: 'Pagas' });
  return list;
});

const filtered = computed(() => {
  if (tab.value === 'open')
    return financial.installments.filter(i =>
      ['pendente', 'vencido', 'parcial'].includes(i.status)
    );
  if (tab.value === 'paid')
    return financial.installments.filter(i => i.status === 'recebido');
  return financial.installments;
});

const emptyDescription = computed(() => {
  if (tab.value === 'open')
    return 'Você está em dia. As próximas parcelas aparecem aqui antes do vencimento.';
  if (tab.value === 'paid') return 'Os recibos das parcelas pagas ficam aqui.';
  return 'Nenhuma parcela cadastrada ainda.';
});

function changeTab(key) {
  tab.value = key;
}

onMounted(async () => {
  await financial.fetchSummary();
  await financial.fetchInstallments('all');
});
</script>

<template>
  <AppShell>
    <PageHeader title="Financeiro" subtitle="Suas parcelas e pagamentos" />

    <div class="pp-fin">
      <!-- Summary cards -->
      <section class="pp-fin__summary">
        <div
          class="pp-fin__summary-block"
          :class="{ 'pp-fin__summary-block--danger': financial.hasOverdue }"
        >
          <div class="pp-fin__summary-label">Em aberto</div>
          <div class="pp-fin__summary-value">
            {{ formatCurrency(financial.totals.open_amount_cents) }}
          </div>
          <div
            v-if="financial.totals.open_count > 0"
            class="pp-fin__summary-hint"
          >
            {{ financial.totals.open_count }} parcela{{
              financial.totals.open_count > 1 ? 's' : ''
            }}
            <span v-if="financial.hasOverdue" class="pp-fin__overdue">
              · {{ financial.totals.overdue_count }} vencida{{
                financial.totals.overdue_count > 1 ? 's' : ''
              }}
            </span>
          </div>
        </div>
        <div class="pp-fin__summary-block">
          <div class="pp-fin__summary-label">Pago este ano</div>
          <div class="pp-fin__summary-value pp-fin__summary-value--success">
            {{ formatCurrency(financial.totals.paid_year_cents) }}
          </div>
        </div>
      </section>

      <!-- Próxima parcela em destaque -->
      <section v-if="financial.nextDue">
        <h3 class="pp-fin__section-title">Próxima parcela</h3>
        <InstallmentCard :installment="financial.nextDue" />
      </section>

      <!-- Tabs -->
      <section>
        <div class="pp-fin__tabs">
          <button
            v-for="t in tabs"
            :key="t.key"
            type="button"
            class="pp-fin__tab"
            :class="{ 'pp-fin__tab--active': tab === t.key }"
            @click="changeTab(t.key)"
          >
            {{ t.label }}
          </button>
        </div>

        <div v-if="financial.loading" class="pp-fin__loading">Carregando…</div>
        <ul v-else-if="filtered.length > 0" class="pp-fin__list">
          <li v-for="i in filtered" :key="i.id">
            <InstallmentCard :installment="i" />
          </li>
        </ul>
        <BaseCard v-else>
          <EmptyState
            title="Sem parcelas neste filtro"
            :description="emptyDescription"
          >
            <template #icon><IconCheck :size="28" /></template>
          </EmptyState>
        </BaseCard>
      </section>

      <p class="pp-fin__footer">
        Pagamento online (PIX, boleto e cartão) entra na Sprint F. Por ora, fale
        com a clínica para regularizar.
      </p>
    </div>
  </AppShell>
</template>

<style scoped>
.pp-fin {
  padding: 8px var(--pp-content-pad-x) 24px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}
@media (min-width: 1024px) {
  .pp-fin {
    gap: 28px;
  }
  .pp-fin__list {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
  }
  .pp-fin__summary-block {
    padding: 20px 22px;
  }
  .pp-fin__summary-value {
    font-size: 26px;
  }
}

.pp-fin__summary {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.pp-fin__summary-block {
  background: #fff;
  border: 1px solid var(--pp-color-border);
  border-radius: 16px;
  padding: 16px;
}
.pp-fin__summary-block--danger {
  border-color: #fecaca;
  background: #fef2f2;
}
.pp-fin__summary-label {
  font-size: 11px;
  color: var(--pp-color-text-muted);
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
.pp-fin__summary-value {
  font-size: 22px;
  font-weight: 800;
  color: var(--pp-color-text);
  margin-top: 6px;
}
.pp-fin__summary-value--success {
  color: #047857;
}
.pp-fin__summary-hint {
  font-size: 11px;
  color: var(--pp-color-text-muted);
  margin-top: 4px;
}
.pp-fin__overdue {
  color: #b91c1c;
  font-weight: 600;
}

.pp-fin__section-title {
  margin: 0 0 8px;
  font-size: 13px;
  font-weight: 700;
  color: var(--pp-color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.pp-fin__tabs {
  display: flex;
  gap: 4px;
  padding: 4px;
  background: #f1f5f9;
  border-radius: 12px;
  margin-bottom: 12px;
}
.pp-fin__tab {
  flex: 1;
  padding: 8px 12px;
  border: none;
  background: transparent;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  color: var(--pp-color-text-muted);
  border-radius: 8px;
  transition: all 120ms ease;
}
.pp-fin__tab--active {
  background: #fff;
  color: var(--pp-color-text);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
}

.pp-fin__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}
.pp-fin__list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.pp-fin__footer {
  text-align: center;
  padding: 8px 16px;
  font-size: 12px;
  color: var(--pp-color-text-muted);
}
</style>
