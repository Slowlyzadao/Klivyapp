<script setup>
/**
 * Extrato por Conta — wireframe Hub Relatórios (2026-05-23).
 *
 * Selector de conta + lista cronológica de movimentações com saldo
 * corrente. Mostra saldo inicial estimado (current - movimentos futuros),
 * fluxo dentro do período, e saldo final.
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL, bankKindLabel } from '../../composables/useMoney';

const props = defineProps({
  from: { type: String, required: true },
  to:   { type: String, required: true },
});

const notifyError = msg => useNotification.error(msg);
const loading = ref(false);
const data = ref({ summary: {}, entries: [], bank_account: null });
const bankAccounts = ref([]);
const selectedBankId = ref(null);

const bankOptions = computed(() =>
  bankAccounts.value.map(b => ({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` })),
);

async function loadAccounts() {
  try {
    const res = await FinancialV2.bankAccounts.index({ active: 'true' });
    bankAccounts.value = res.data?.data || [];
    if (bankAccounts.value.length && !selectedBankId.value) {
      selectedBankId.value = bankAccounts.value[0].id;
    }
  } catch {
    bankAccounts.value = [];
  }
}

async function load() {
  if (!selectedBankId.value) return;
  loading.value = true;
  try {
    const res = await FinancialV2.reports.accountStatement({
      from: props.from, to: props.to, bank_account_id: selectedBankId.value,
    });
    data.value = res.data || { summary: {}, entries: [], bank_account: null };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar extrato.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to, selectedBankId.value], load);
onMounted(async () => { await loadAccounts(); await load(); });

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

defineExpose({
  exportCsv: () => {
    const rows = [['Data', 'Tipo', 'Descrição', 'Direção', 'Valor', 'Saldo']];
    data.value.entries.forEach(e => {
      rows.push([
        formatDateBR(e.date), e.kind_label, e.description,
        e.direction === 'in' ? 'Entrada' : 'Saída',
        (e.signed_amount_cents / 100).toFixed(2).replace('.', ','),
        (e.balance_cents / 100).toFixed(2).replace('.', ','),
      ]);
    });
    return rows;
  },
});
</script>

<template>
  <div class="rep-detail">
    <div class="rep-detail__filter">
      <label class="rep-detail__filter-label">Conta</label>
      <div class="rep-detail__filter-select">
        <FormSelect
          v-model="selectedBankId"
          :options="bankOptions"
          placeholder="Selecione a conta"
          searchable
          auto-searchable
        />
      </div>
    </div>

    <div v-if="data.bank_account" class="finv2-kpis">
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-wallet w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Saldo inicial</span>
          <strong class="finv2-kpi__value">{{ centsToBRL(data.summary.initial_balance_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--positive"><i class="i-lucide-arrow-down-to-line w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Entradas</span>
          <strong class="finv2-kpi__value finv2-kpi__value--positive">{{ centsToBRL(data.summary.income_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--danger"><i class="i-lucide-arrow-up-from-line w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Saídas</span>
          <strong class="finv2-kpi__value finv2-kpi__value--danger">{{ centsToBRL(data.summary.outflow_cents || 0) }}</strong>
        </div>
      </div>
      <div class="finv2-kpi">
        <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-scale w-4 h-4" /></div>
        <div class="finv2-kpi__content">
          <span class="finv2-kpi__label">Saldo final</span>
          <strong
            class="finv2-kpi__value"
            :class="(data.summary.final_balance_cents || 0) >= 0 ? 'finv2-kpi__value--positive' : 'finv2-kpi__value--danger'"
          >
            {{ centsToBRL(data.summary.final_balance_cents || 0) }}
          </strong>
        </div>
      </div>
    </div>

    <div v-if="loading" class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
    <div v-else-if="!selectedBankId" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-wallet w-7 h-7" /></div>
      <p class="finv2-state__title">Selecione uma conta</p>
    </div>
    <div v-else-if="data.entries.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-inbox w-7 h-7" /></div>
      <p class="finv2-state__title">Sem movimentações no período</p>
      <p class="finv2-state__hint">Ajuste o período ou selecione outra conta.</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Data</th>
            <th>Tipo</th>
            <th>Descrição</th>
            <th class="finv2-table__th-num">Valor</th>
            <th class="finv2-table__th-num">Saldo</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in data.entries" :key="e.id">
            <td class="finv2-table__td-date">{{ formatDateBR(e.date) }}</td>
            <td>
              <span class="rep-detail__kind-pill">{{ e.kind_label }}</span>
            </td>
            <td>{{ e.description }}</td>
            <td
              class="finv2-table__td-num finv2-table__td-num--strong"
              :class="e.direction === 'in' ? 'rep-detail__amt--in' : 'rep-detail__amt--out'"
            >
              {{ e.direction === 'in' ? '+' : '−' }} {{ centsToBRL(e.amount_cents) }}
            </td>
            <td
              class="finv2-table__td-num"
              :class="e.balance_cents < 0 ? 'rep-detail__amt--out' : ''"
            >
              {{ centsToBRL(e.balance_cents) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-detail__filter {
  display: flex; align-items: center; gap: 12px; margin-bottom: 4px;
}
.rep-detail__filter-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
}
.rep-detail__filter-select { flex: 1; max-width: 360px; }

.rep-detail__kind-pill {
  display: inline-flex; align-items: center;
  padding: 2px 8px; border-radius: 4px;
  font-size: 11px; font-weight: 500;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
}
.rep-detail__amt--in { color: #047857; }
.rep-detail__amt--out { color: #b91c1c; }
:root.dark .rep-detail__amt--in { color: #6ee7b7; }
:root.dark .rep-detail__amt--out { color: #fca5a5; }
</style>
