<script setup>
/**
 * Caixa físico — v2 (canon §4.8).
 *
 * Gerencia sessões de caixa (abertura/sangria/suprimento/fechamento) com
 * suporte a quebra automática. Bloqueia lançamento em dinheiro com data
 * em sessão fechada.
 *
 * UI premium:
 *   - Layout `.finv2-page` (scroll + sticky header).
 *   - FormSelect pra escolher conta de caixa.
 *   - Badge global pra status da sessão.
 *   - KPIs com ícones e cores semânticas.
 *   - Mobile: cards stacked com ações empilhadas.
 *
 * Observação: ainda usa `prompt()` nativo pra ações pontuais (abrir,
 * sangria, suprimento, fechar). Substituir por modais dedicados é refactor
 * separado — fora do escopo desta passada visual.
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL, brlInputToCents } from '../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const cashAccounts = ref([]);
const selectedBankId = ref(null);
const today = new Date().toISOString().slice(0, 10);
const todayRegister = ref(null);
const history = ref([]);
const loading = ref(false);
const currentPage = ref(1);
const perPage = ref(10);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const cashAccountOptions = computed(() =>
  cashAccounts.value.map(b => ({ value: b.id, label: b.name })),
);

const STATUS_BADGE = {
  open:    { color: 'emerald', icon: 'i-lucide-circle-dot',     label: 'Aberto' },
  closed:  { color: 'slate',   icon: 'i-lucide-lock',           label: 'Fechado' },
  reopen:  { color: 'amber',   icon: 'i-lucide-refresh-cw',     label: 'Reaberto' },
};

function statusBadge(status) {
  return STATUS_BADGE[status] || STATUS_BADGE.closed;
}

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

async function loadCashAccounts() {
  try {
    const { data } = await FinancialV2.bankAccounts.index({ kind: 'cash', active: 'true' });
    cashAccounts.value = data?.data || [];
    if (cashAccounts.value.length === 1) selectedBankId.value = cashAccounts.value[0].id;
  } catch {
    cashAccounts.value = [];
  }
}

async function loadToday() {
  if (!selectedBankId.value) return;
  try {
    const { data } = await FinancialV2.cashRegisters.index({
      bank_account_id: selectedBankId.value, from: today, to: today,
    });
    todayRegister.value = (data?.data || [])[0] || null;
  } catch {
    todayRegister.value = null;
  }
}

async function loadHistory() {
  if (!selectedBankId.value) return;
  loading.value = true;
  try {
    const { data } = await FinancialV2.cashRegisters.index({
      bank_account_id: selectedBankId.value, status: 'closed',
    });
    history.value = (data?.data || []);
  } finally {
    loading.value = false;
  }
}

const paginatedHistory = computed(() => {
  const start = (currentPage.value - 1) * perPage.value;
  return history.value.slice(start, start + perPage.value);
});

async function openCash() {
  const opening = prompt('Saldo inicial em dinheiro (ex: 100,00):');
  if (!opening) return;
  try {
    await FinancialV2.cashRegisters.open({
      bank_account_id: selectedBankId.value,
      opening_balance_cents: brlInputToCents(opening),
      session_date: today,
    });
    notifySuccess('Caixa aberto.');
    await loadToday();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao abrir caixa.');
  }
}

async function closeCash() {
  if (!todayRegister.value) return;
  const counted = prompt(
    `Esperado: ${centsToBRL(todayRegister.value.calculated_expected_cents)}\n` +
    'Valor contado em dinheiro:'
  );
  if (!counted) return;
  try {
    const { data } = await FinancialV2.cashRegisters.close(todayRegister.value.id, {
      counted_balance_cents: brlInputToCents(counted),
    });
    notifySuccess(`Caixa fechado. Diferença: ${centsToBRL(data.difference_cents)}`);
    await loadToday();
    await loadHistory();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao fechar caixa.');
  }
}

async function withdraw() {
  if (!todayRegister.value) return;
  const banks = (await FinancialV2.bankAccounts.index({ active: 'true' })).data?.data || [];
  const target = banks.find(b => b.kind !== 'cash');
  if (!target) {
    notifyError('Nenhuma conta bancária para depositar');
    return;
  }
  const amount = prompt(`Sangria — depositar em ${target.name}. Valor:`);
  if (!amount) return;
  try {
    await FinancialV2.cashRegisters.withdraw(todayRegister.value.id, {
      to_bank_account_id: target.id,
      amount_cents: brlInputToCents(amount),
    });
    notifySuccess('Sangria registrada.');
    await loadToday();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha na sangria.');
  }
}

async function supplement() {
  if (!todayRegister.value) return;
  const banks = (await FinancialV2.bankAccounts.index({ active: 'true' })).data?.data || [];
  const source = banks.find(b => b.kind !== 'cash');
  if (!source) {
    notifyError('Nenhuma conta bancária para retirar');
    return;
  }
  const amount = prompt(`Suprimento — retirar de ${source.name}. Valor:`);
  if (!amount) return;
  try {
    await FinancialV2.cashRegisters.supplement(todayRegister.value.id, {
      from_bank_account_id: source.id,
      amount_cents: brlInputToCents(amount),
    });
    notifySuccess('Suprimento registrado.');
    await loadToday();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha no suprimento.');
  }
}

async function reopen(register) {
  const reason = prompt('Motivo da reabertura (obrigatório):');
  if (!reason) return;
  try {
    await FinancialV2.cashRegisters.reopen(register.id, { reason });
    notifySuccess('Caixa reaberto.');
    await loadToday();
    await loadHistory();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao reabrir caixa.');
  }
}

async function reloadAll() {
  if (!selectedBankId.value) return;
  await loadToday();
  await loadHistory();
}

onMounted(async () => {
  await loadCashAccounts();
  if (selectedBankId.value) await reloadAll();
});
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Caixa</h1>
        <p class="finv2-page__subtitle">
          Sessões de caixa: abrir, sangria, suprimento e fechar com auditoria.
        </p>
      </div>
      <div class="cashr__bank-selector">
        <FormSelect
          v-model="selectedBankId"
          :options="cashAccountOptions"
          placeholder="Selecione o caixa"
          @update:model-value="reloadAll"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- Sessão de hoje -->
      <section v-if="!selectedBankId" class="finv2-state">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-wallet w-7 h-7" /></div>
        <p class="finv2-state__title">Selecione um caixa</p>
        <p class="finv2-state__hint">Escolha uma conta de caixa no topo pra ver/operar.</p>
      </section>

      <section v-else-if="!todayRegister" class="cashr__empty-day">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-calendar-x w-7 h-7" /></div>
        <p class="finv2-state__title">Nenhuma sessão hoje</p>
        <p class="finv2-state__hint">Abra o caixa para começar a registrar movimentações em dinheiro.</p>
        <BeclinicButton
          variant="solid"
          color="teal"
          icon="i-lucide-unlock"
          label="Abrir caixa"
          @click="openCash"
        />
      </section>

      <section v-else class="cashr__open-card">
        <header class="cashr__open-header">
          <div class="cashr__open-title">
            <h2>Sessão de hoje</h2>
            <Badge
              :label="statusBadge(todayRegister.status).label"
              :color="statusBadge(todayRegister.status).color"
              :icon="statusBadge(todayRegister.status).icon"
              size="xs"
            />
          </div>
        </header>

        <div class="finv2-kpis">
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-key w-4 h-4" /></div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Abertura</span>
              <strong class="finv2-kpi__value">{{ centsToBRL(todayRegister.opening_balance_cents) }}</strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--positive"><i class="i-lucide-calculator w-4 h-4" /></div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Esperado agora</span>
              <strong class="finv2-kpi__value finv2-kpi__value--positive">
                {{ centsToBRL(todayRegister.calculated_expected_cents) }}
              </strong>
            </div>
          </div>
          <div v-if="todayRegister.status !== 'open' && todayRegister.difference_cents != null" class="finv2-kpi">
            <div
              class="finv2-kpi__icon"
              :class="todayRegister.difference_cents < 0 ? 'finv2-kpi__icon--danger' : 'finv2-kpi__icon--positive'"
            >
              <i class="i-lucide-scale w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Diferença</span>
              <strong
                class="finv2-kpi__value"
                :class="todayRegister.difference_cents < 0 ? 'finv2-kpi__value--danger' : 'finv2-kpi__value--positive'"
              >
                {{ centsToBRL(todayRegister.difference_cents) }}
              </strong>
            </div>
          </div>
        </div>

        <div v-if="todayRegister.status === 'open'" class="cashr__actions">
          <BeclinicButton variant="faded"  color="teal"  icon="i-lucide-arrow-down-to-line" label="Suprimento" @click="supplement" />
          <BeclinicButton variant="faded"  color="amber" icon="i-lucide-arrow-up-from-line" label="Sangria"     @click="withdraw" />
          <BeclinicButton variant="solid"  color="ruby"  icon="i-lucide-lock"               label="Fechar caixa" @click="closeCash" />
        </div>
        <div v-else class="cashr__actions">
          <p class="cashr__closed-info">
            Fechado em <strong>{{ formatDateBR(todayRegister.closed_at) }}</strong>
            <template v-if="todayRegister.difference_cents != null">
              · diferença <strong>{{ centsToBRL(todayRegister.difference_cents) }}</strong>
            </template>
          </p>
          <BeclinicButton variant="ghost" color="slate" icon="i-lucide-unlock" label="Reabrir" @click="reopen(todayRegister)" />
        </div>
      </section>

      <!-- Histórico -->
      <section v-if="selectedBankId" class="cashr__history">
        <h2 class="cashr__history-title">Histórico de sessões fechadas</h2>

        <div class="finv2-table-wrap finv2-hide-mobile">
          <table class="finv2-table">
            <thead>
              <tr>
                <th>Data</th>
                <th class="finv2-table__th-num">Abertura</th>
                <th class="finv2-table__th-num">Esperado</th>
                <th class="finv2-table__th-num">Contado</th>
                <th class="finv2-table__th-num">Diferença</th>
                <th class="finv2-table__th-actions">Ações</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading">
                <td colspan="6">
                  <div class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
                </td>
              </tr>
              <tr v-else-if="history.length === 0">
                <td colspan="6">
                  <div class="finv2-state">
                    <div class="finv2-state__icon-wrap"><i class="i-lucide-history w-7 h-7" /></div>
                    <p class="finv2-state__title">Nenhuma sessão fechada</p>
                    <p class="finv2-state__hint">Quando você fechar caixas, eles aparecem aqui.</p>
                  </div>
                </td>
              </tr>
              <tr v-for="r in paginatedHistory" v-else :key="r.id">
                <td class="finv2-table__td-date">{{ formatDateBR(r.session_date) }}</td>
                <td class="finv2-table__td-num">{{ centsToBRL(r.opening_balance_cents) }}</td>
                <td class="finv2-table__td-num">{{ centsToBRL(r.expected_balance_cents) }}</td>
                <td class="finv2-table__td-num">{{ centsToBRL(r.counted_balance_cents) }}</td>
                <td
                  class="finv2-table__td-num finv2-table__td-num--strong"
                  :class="{ 'cashr__diff--neg': r.difference_cents < 0, 'cashr__diff--pos': r.difference_cents > 0 }"
                >
                  {{ centsToBRL(r.difference_cents) }}
                </td>
                <td class="finv2-table__td-actions">
                  <BeclinicButton size="xs" variant="ghost" color="slate" icon="i-lucide-unlock" @click="reopen(r)" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Mobile: cards do histórico -->
        <div class="finv2-cards finv2-show-mobile">
          <div v-if="loading" class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
          <div v-else-if="history.length === 0" class="finv2-state">
            <div class="finv2-state__icon-wrap"><i class="i-lucide-history w-7 h-7" /></div>
            <p class="finv2-state__title">Nenhuma sessão fechada</p>
          </div>
          <article v-for="r in paginatedHistory" v-else :key="`m-${r.id}`" class="finv2-card">
            <div class="cashr__card-row">
              <strong>{{ formatDateBR(r.session_date) }}</strong>
              <BeclinicButton size="xs" variant="ghost" color="slate" icon="i-lucide-unlock" label="Reabrir" @click="reopen(r)" />
            </div>
            <div class="cashr__card-grid">
              <div><span class="cashr__card-label">Abertura</span><strong>{{ centsToBRL(r.opening_balance_cents) }}</strong></div>
              <div><span class="cashr__card-label">Contado</span><strong>{{ centsToBRL(r.counted_balance_cents) }}</strong></div>
              <div :class="{ 'cashr__diff--neg': r.difference_cents < 0, 'cashr__diff--pos': r.difference_cents > 0 }">
                <span class="cashr__card-label">Diferença</span>
                <strong>{{ centsToBRL(r.difference_cents) }}</strong>
              </div>
            </div>
          </article>
        </div>

        <Pagination
          v-model:current-page="currentPage"
          v-model:per-page="perPage"
          :total-count="history.length"
          item-label="sessões"
        />
      </section>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Layout, KPIs, table, chips e estados vêm do _layout.scss global. */

.cashr__bank-selector { min-width: 220px; max-width: 280px; }

.cashr__empty-day {
  display: flex; flex-direction: column; align-items: center; gap: 12px;
  padding: 48px 20px; text-align: center;
  background: rgb(var(--slate-2));
  border: 1px dashed rgb(var(--slate-5));
  border-radius: 14px;
}

.cashr__open-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px;
  display: flex; flex-direction: column; gap: 16px;
}
.cashr__open-header { display: flex; justify-content: space-between; align-items: center; }
.cashr__open-title  { display: flex; align-items: center; gap: 10px;
  h2 { margin: 0; font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); }
}
.cashr__actions { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
.cashr__closed-info {
  flex: 1; margin: 0; font-size: 13px; color: rgb(var(--slate-11));
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}

.cashr__history {
  display: flex; flex-direction: column; gap: 12px;
}
.cashr__history-title {
  margin: 0;
  font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em;
  color: rgb(var(--slate-9)); font-weight: 600;
}

/* Diferença colorida (verde positivo, vermelho negativo) */
.cashr__diff--neg, .cashr__diff--neg strong { color: #b91c1c; }
.cashr__diff--pos, .cashr__diff--pos strong { color: #047857; }
:root.dark .cashr__diff--neg, :root.dark .cashr__diff--neg strong { color: #fca5a5; }
:root.dark .cashr__diff--pos, :root.dark .cashr__diff--pos strong { color: #6ee7b7; }

/* Mobile cards específicos */
.cashr__card-row { display: flex; justify-content: space-between; align-items: center; }
.cashr__card-grid {
  display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px;
  padding-top: 10px; border-top: 1px solid rgb(var(--slate-3));
}
.cashr__card-label {
  display: block; font-size: 10.5px; text-transform: uppercase;
  letter-spacing: 0.04em; color: rgb(var(--slate-9)); margin-bottom: 3px;
}
</style>
