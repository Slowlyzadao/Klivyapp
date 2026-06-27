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
 * Refactor 2026-05-23: substituídos os 5 prompt() nativos por
 * CashRegisterActionModalV2 (multi-mode). Diferença em tempo real no fechamento.
 */
import { ref, computed, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import CashRegisterActionModalV2 from '../components/CashRegisterActionModalV2.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const router = useRouter();
const route = useRoute();
const cashAccounts = ref([]);
// `loadingAccounts` distingue "carregando" de "carregado e vazio" — sem isso,
// o empty state aparece no 1º frame de mount com a mensagem errada ("nenhuma
// conta cadastrada") quando na verdade ainda estava carregando.
const loadingAccounts = ref(true);
const selectedBankId = ref(null);
const today = new Date().toISOString().slice(0, 10);
const todayRegister = ref(null);
const history = ref([]);
const loading = ref(false);
const currentPage = ref(1);
const perPage = ref(10);

// KPIs derivados — 4 do wireframe canon §4.8:
//   - Caixa de hoje (status textual)
//   - Total histórico (count de sessões registradas)
//   - Diferença acumulada (soma signed das diferenças do histórico)
//   - Saldo caixa físico (current_balance_cents da BankAccount kind=cash)
const selectedCashAccount = computed(() =>
  cashAccounts.value.find(b => b.id === selectedBankId.value) || null,
);
const totalHistoryCount = computed(() => history.value.length);
const accumulatedDifferenceCents = computed(() =>
  history.value.reduce((sum, r) => sum + (r.difference_cents || 0), 0),
);
const physicalBalanceCents = computed(() =>
  selectedCashAccount.value?.current_balance_cents ?? 0,
);
const todayStatusLabel = computed(() => {
  if (!todayRegister.value) return 'Fechado';
  return statusBadge(todayRegister.value.status).label;
});
const todayStatusHint = computed(() => {
  if (!todayRegister.value) return 'use o botão Abrir';
  if (todayRegister.value.status === 'open') return 'aberto agora';
  if (todayRegister.value.closed_at) {
    return `fechado em ${formatDateBR(todayRegister.value.closed_at)}`;
  }
  return '';
});

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
  loadingAccounts.value = true;
  try {
    const { data } = await FinancialV2.bankAccounts.index({ kind: 'cash', active: 'true' });
    cashAccounts.value = data?.data || [];
    if (cashAccounts.value.length === 1) selectedBankId.value = cashAccounts.value[0].id;
  } catch {
    cashAccounts.value = [];
  } finally {
    loadingAccounts.value = false;
  }
}

// CTA do empty state "nenhuma cash account": leva o admin direto pra aba
// "Contas Bancárias" do Settings financeiro. Sem isso, o operador olha
// pra essa tela vazia sem ideia do que fazer (não há "topo" pra escolher).
function goToBankAccountsSettings() {
  router.push({
    name: 'financial_v2_settings_tab',
    params: { accountId: route.params.accountId, tab: 'bank-accounts' },
  });
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

// ── Modal de ação (substitui os 5 prompts nativos) ──────────────────
// Mode pode ser: open | close | withdraw | supplement | reopen.
// `actionContext` carrega referências resolvidas (target bank pra sangria etc).
const actionModalShow = ref(false);
const actionMode = ref(null);
const actionContext = ref({});

function startAction(mode, context = {}) {
  actionMode.value = mode;
  actionContext.value = context;
  actionModalShow.value = true;
}

function closeAction() {
  actionModalShow.value = false;
  actionMode.value = null;
  actionContext.value = {};
}

async function onActionConfirm(payload) {
  const mode = actionMode.value;
  const ctx = actionContext.value;
  closeAction();

  try {
    if (mode === 'open') {
      await FinancialV2.cashRegisters.open({
        bank_account_id: selectedBankId.value,
        opening_balance_cents: payload.opening_balance_cents,
        session_date: today,
      });
      notifySuccess('Caixa aberto.');
      await loadToday();
    } else if (mode === 'close') {
      const { data } = await FinancialV2.cashRegisters.close(todayRegister.value.id, {
        counted_balance_cents: payload.counted_balance_cents,
      });
      notifySuccess(`Caixa fechado. Diferença: ${centsToBRL(data.difference_cents)}`);
      await loadToday();
      await loadHistory();
    } else if (mode === 'withdraw') {
      await FinancialV2.cashRegisters.withdraw(todayRegister.value.id, {
        to_bank_account_id: ctx.bank.id,
        amount_cents: payload.amount_cents,
      });
      notifySuccess('Sangria registrada.');
      await loadToday();
    } else if (mode === 'supplement') {
      await FinancialV2.cashRegisters.supplement(todayRegister.value.id, {
        from_bank_account_id: ctx.bank.id,
        amount_cents: payload.amount_cents,
      });
      notifySuccess('Suprimento registrado.');
      await loadToday();
    } else if (mode === 'reopen') {
      await FinancialV2.cashRegisters.reopen(ctx.register.id, { reason: payload.reason });
      notifySuccess('Caixa reaberto.');
      await loadToday();
      await loadHistory();
    }
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao executar ação.');
  }
}

function openCash() {
  startAction('open');
}

function closeCash() {
  if (!todayRegister.value) return;
  startAction('close');
}

async function withdraw() {
  if (!todayRegister.value) return;
  const banks = (await FinancialV2.bankAccounts.index({ active: 'true' })).data?.data || [];
  const target = banks.find(b => b.kind !== 'cash');
  if (!target) {
    notifyError('Nenhuma conta bancária para depositar.');
    return;
  }
  startAction('withdraw', { bank: target });
}

async function supplement() {
  if (!todayRegister.value) return;
  const banks = (await FinancialV2.bankAccounts.index({ active: 'true' })).data?.data || [];
  const source = banks.find(b => b.kind !== 'cash');
  if (!source) {
    notifyError('Nenhuma conta bancária para retirar.');
    return;
  }
  startAction('supplement', { bank: source });
}

function reopen(register) {
  startAction('reopen', { register });
}

// Nome do banco passado pro modal quando aplicável
const actionBankName = computed(() => actionContext.value?.bank?.name || '');

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
          Abertura, movimentação e fechamento diário.
        </p>
      </div>
      <div class="cashr__header-actions">
        <!-- Selector só aparece se houver MAIS de 1 caixa físico. Com 1 só,
             é ruído visual (auto-selecionado no loadCashAccounts). -->
        <div v-if="cashAccounts.length > 1" class="cashr__bank-selector">
          <FormSelect
            v-model="selectedBankId"
            :options="cashAccountOptions"
            placeholder="Selecione o caixa"
            @update:model-value="reloadAll"
          />
        </div>
        <BeclinicButton
          v-if="selectedBankId && !todayRegister"
          variant="solid"
          color="teal"
          icon="i-lucide-unlock"
          label="Abrir Caixa Hoje"
          @click="openCash"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- 4 KPIs do topo (canon wireframe §4.8) — sempre visíveis quando
           há caixa selecionado. Dão visão macro independente do estado da
           sessão atual. -->
      <div v-if="selectedBankId" class="finv2-kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-wallet w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Caixa de hoje</span>
            <strong class="finv2-kpi__value">{{ todayStatusLabel }}</strong>
            <span class="finv2-kpi__hint">{{ todayStatusHint }}</span>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-history w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total histórico</span>
            <strong class="finv2-kpi__value">{{ totalHistoryCount }}</strong>
            <span class="finv2-kpi__hint">
              {{ totalHistoryCount === 1 ? 'caixa registrado' : 'caixas registrados' }}
            </span>
          </div>
        </div>
        <div class="finv2-kpi">
          <div
            class="finv2-kpi__icon"
            :class="accumulatedDifferenceCents < 0
              ? 'finv2-kpi__icon--danger'
              : 'finv2-kpi__icon--positive'"
          >
            <i class="i-lucide-scale w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Diferença acumulada</span>
            <strong
              class="finv2-kpi__value"
              :class="accumulatedDifferenceCents < 0
                ? 'finv2-kpi__value--danger'
                : 'finv2-kpi__value--positive'"
            >
              {{ centsToBRL(accumulatedDifferenceCents) }}
            </strong>
            <span class="finv2-kpi__hint">sobra/falta histórica</span>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--warning">
            <i class="i-lucide-banknote w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Saldo caixa físico</span>
            <strong class="finv2-kpi__value">{{ centsToBRL(physicalBalanceCents) }}</strong>
            <span v-if="selectedCashAccount" class="finv2-kpi__hint">
              {{ selectedCashAccount.name }}
            </span>
          </div>
        </div>
      </div>

      <!-- Sessão de hoje -->
      <section v-if="loadingAccounts" class="finv2-state">
        <div class="finv2-spinner" />
        <p class="finv2-state__hint">Carregando contas de caixa…</p>
      </section>

      <!-- Empty state diferenciado: nenhuma cash account cadastrada.
           Sem isso, operador olhava pra "Selecione um caixa no topo" mas
           não havia nada no topo (selector tem v-if=length > 1). UX-101:
           toda mensagem tem que apontar pra ação concreta. -->
      <section v-else-if="cashAccounts.length === 0" class="finv2-state cashr__empty-setup">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-wallet w-7 h-7" /></div>
        <p class="finv2-state__title">Nenhum caixa físico cadastrado</p>
        <p class="finv2-state__hint">
          Pra usar abertura, sangria e fechamento diário, cadastre primeiro
          uma conta bancária do tipo <strong>Caixa</strong> em
          <em>Configurações → Contas Bancárias</em>.
        </p>
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-plus"
          label="Cadastrar conta de caixa"
          @click="goToBankAccountsSettings"
        />
      </section>

      <section v-else-if="!selectedBankId" class="finv2-state">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-wallet w-7 h-7" /></div>
        <p class="finv2-state__title">Selecione um caixa</p>
        <p class="finv2-state__hint">Escolha uma conta de caixa no topo pra ver/operar.</p>
      </section>

      <section v-else-if="!todayRegister" class="cashr__empty-day">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-calendar-x w-7 h-7" /></div>
        <p class="finv2-state__title">Nenhuma sessão hoje</p>
        <p class="finv2-state__hint">Use o botão <strong>"Abrir Caixa Hoje"</strong> no topo pra começar.</p>
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
              <span class="finv2-kpi__label">Saldo inicial</span>
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
          <BeclinicButton variant="faded"  color="blue"  icon="i-lucide-arrow-down-to-line" label="Suprimento" @click="supplement" />
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
        <header class="cashr__history-header">
          <h2 class="cashr__history-title">Histórico de caixas</h2>
          <p class="cashr__history-sub">Aberturas, fechamentos, diferenças</p>
        </header>

        <div class="finv2-table-wrap finv2-hide-mobile">
          <table class="finv2-table">
            <thead>
              <tr>
                <th>Data</th>
                <th>Responsável</th>
                <th class="finv2-table__th-num">Saldo inicial</th>
                <th class="finv2-table__th-num">Esperado</th>
                <th class="finv2-table__th-num">Físico</th>
                <th class="finv2-table__th-num">Diferença</th>
                <th>Status</th>
                <th class="finv2-table__th-actions">Ações</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loading">
                <td colspan="8">
                  <div class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
                </td>
              </tr>
              <tr v-else-if="history.length === 0">
                <td colspan="8">
                  <div class="finv2-state">
                    <div class="finv2-state__icon-wrap"><i class="i-lucide-history w-7 h-7" /></div>
                    <p class="finv2-state__title">Nenhuma sessão fechada</p>
                    <p class="finv2-state__hint">Quando você fechar caixas, eles aparecem aqui.</p>
                  </div>
                </td>
              </tr>
              <tr v-for="r in paginatedHistory" v-else :key="r.id">
                <td class="finv2-table__td-date">{{ formatDateBR(r.session_date) }}</td>
                <td>
                  <span v-if="r.operator?.name">{{ r.operator.name }}</span>
                  <span v-else class="finv2-table__td-muted">—</span>
                </td>
                <td class="finv2-table__td-num">{{ centsToBRL(r.opening_balance_cents) }}</td>
                <td class="finv2-table__td-num">{{ centsToBRL(r.expected_balance_cents) }}</td>
                <td class="finv2-table__td-num">{{ centsToBRL(r.counted_balance_cents) }}</td>
                <td
                  class="finv2-table__td-num finv2-table__td-num--strong"
                  :class="{ 'cashr__diff--neg': r.difference_cents < 0, 'cashr__diff--pos': r.difference_cents > 0 }"
                >
                  {{ centsToBRL(r.difference_cents) }}
                </td>
                <td>
                  <Badge
                    :label="statusBadge(r.status).label"
                    :color="statusBadge(r.status).color"
                    :icon="statusBadge(r.status).icon"
                    size="xs"
                  />
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
              <div><span class="cashr__card-label">Saldo inicial</span><strong>{{ centsToBRL(r.opening_balance_cents) }}</strong></div>
              <div><span class="cashr__card-label">Físico</span><strong>{{ centsToBRL(r.counted_balance_cents) }}</strong></div>
              <div :class="{ 'cashr__diff--neg': r.difference_cents < 0, 'cashr__diff--pos': r.difference_cents > 0 }">
                <span class="cashr__card-label">Diferença</span>
                <strong>{{ centsToBRL(r.difference_cents) }}</strong>
              </div>
            </div>
            <div v-if="r.operator?.name" class="cashr__card-operator">
              <span class="cashr__card-label">Responsável</span>
              <strong>{{ r.operator.name }}</strong>
            </div>
            <div class="cashr__card-status">
              <Badge
                :label="statusBadge(r.status).label"
                :color="statusBadge(r.status).color"
                :icon="statusBadge(r.status).icon"
                size="xs"
              />
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

    <CashRegisterActionModalV2
      v-if="actionModalShow"
      :show="actionModalShow"
      :mode="actionMode"
      :register="todayRegister"
      :bank-account-name="actionBankName"
      @close="closeAction"
      @confirm="onActionConfirm"
    />
  </div>
</template>

<style scoped lang="scss">
/* Layout, KPIs, table, chips e estados vêm do _layout.scss global. */

.cashr__header-actions {
  display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
}
.cashr__bank-selector { min-width: 220px; max-width: 280px; }

.cashr__empty-day {
  display: flex; flex-direction: column; align-items: center; gap: 12px;
  padding: 48px 20px; text-align: center;
  background: rgb(var(--slate-2));
  border: 1px dashed rgb(var(--slate-5));
  border-radius: 14px;
}

/* Empty state com CTA pro setup inicial — herda layout de .finv2-state
   global, só adiciona espaço entre o hint e o botão de ação. */
.cashr__empty-setup {
  gap: 14px;
  .finv2-state__hint { max-width: 480px; line-height: 1.5; }
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
.cashr__history-header { display: flex; flex-direction: column; gap: 2px; }
.cashr__history-title {
  margin: 0;
  font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em;
  color: rgb(var(--slate-9)); font-weight: 600;
}
.cashr__history-sub {
  margin: 0; font-size: 12px; color: rgb(var(--slate-9));
}
.cashr__card-operator,
.cashr__card-status {
  display: flex; justify-content: space-between; align-items: center;
  padding-top: 8px; border-top: 1px solid rgb(var(--slate-3));
  font-size: 12px;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
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
