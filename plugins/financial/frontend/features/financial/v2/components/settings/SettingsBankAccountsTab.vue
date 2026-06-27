<script setup>
/**
 * Aba "Contas Bancárias e Caixas" — wireframe Setup #4 (2026-05-23).
 *
 * Estrutura visual (ver mockup canon):
 *   1. Header sticky com título + subtitle "Setup #4 · Onde o dinheiro entra e sai"
 *      e botão "+ Adicionar" no canto direito.
 *   2. 3 KPI cards no topo: Contas Ativas, Saldo Inicial Total, Saldo Estimado Atual.
 *   3. Tabela 8 colunas: cor, apelido, banco/tipo, agência/conta, saldo inicial,
 *      padrão (badges RECEB/PGTO), status, ações.
 *   4. Modal externo BankAccountFormModalV2 — 11 campos incluindo Cor (paleta) e
 *      Data de Corte (DatePickerBR).
 *
 * Endpoints:
 *   GET    /financial/v2/bank_accounts?include_summary=true
 *   POST   /financial/v2/bank_accounts
 *   PATCH  /financial/v2/bank_accounts/:id
 *   DELETE /financial/v2/bank_accounts/:id (só se saldo zerado)
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Toggle from '@plugins/beclinic_core/frontend/components/Toggle.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ConfirmDangerModalV2 from '../ConfirmDangerModalV2.vue';
import FinancialV2 from '../../api/financialV2';
import BankAccountFormModalV2 from './BankAccountFormModalV2.vue';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const accounts = ref([]);
const summary = ref({ active_count: 0, total_count: 0, initial_balance_total_cents: 0, estimated_balance_total_cents: 0 });
const loading = ref(false);
const errorState = ref(null);

const showFormModal = ref(false);
const editingAccount = ref(null);

const showDeleteModal = ref(false);
const accountToDelete = ref(null);
const deleting = ref(false);

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const { data } = await FinancialV2.bankAccounts.index({ include_summary: 'true' });
    accounts.value = data?.data || [];
    summary.value = data?.summary || summary.value;
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar contas';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// ── Formatadores ─────────────────────────────────────────────────────
function centsToBRL(cents) {
  if (cents == null) return 'R$ 0,00';
  return 'R$ ' + (cents / 100).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Versão curta pros KPIs grandes (R$ 51K, R$ 2,9M).
function centsToBRLShort(cents) {
  if (cents == null) return 'R$ 0';
  const v = cents / 100;
  if (Math.abs(v) >= 1_000_000) {
    return 'R$ ' + (v / 1_000_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + 'M';
  }
  if (Math.abs(v) >= 1_000) {
    return 'R$ ' + (v / 1_000).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) + 'K';
  }
  return 'R$ ' + v.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}

const KIND_LABEL = {
  checking: 'Corrente',
  savings: 'Poupança',
  cash: 'Caixa',
  card_receivable: 'Maquininha',
};

// Ícone semântico por tipo (mesmo padrão visual de Formas de Pagamento).
// Landmark (corrente/poupança) = banco institucional; wallet = caixa físico
// próximo à recepção; credit-card = maquininha (recebível futuro).
const KIND_ICON = {
  checking: 'i-lucide-landmark',
  savings: 'i-lucide-piggy-bank',
  cash: 'i-lucide-wallet',
  card_receivable: 'i-lucide-credit-card',
};

function kindLabel(kind) {
  return KIND_LABEL[kind] || kind;
}

function kindIcon(kind) {
  return KIND_ICON[kind] || 'i-lucide-landmark';
}

function agencyAccount(acc) {
  if (acc.kind === 'cash') return '—';
  if (!acc.agency && !acc.account_number) return '—';
  return [acc.agency, acc.account_number].filter(Boolean).join(' / ');
}

// ── Ações ─────────────────────────────────────────────────────────────
// Toggle inline ativa/inativa (PATCH update) — mesma metáfora visual de
// Formas de Pagamento. Otimista: atualiza UI já, reverte em caso de erro.
async function onToggleStatus(acc, newActive) {
  const previous = acc.active;
  acc.active = newActive;
  try {
    await FinancialV2.bankAccounts.update(acc.id, { bank_account: { active: newActive } });
    notifySuccess(newActive ? 'Conta ativada.' : 'Conta inativada.');
    await load(); // re-fetch pra atualizar KPIs (active_count)
  } catch (err) {
    acc.active = previous; // rollback otimista
    notifyError(err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao alterar status');
  }
}

function openModalForNew() {
  editingAccount.value = null;
  showFormModal.value = true;
}

function openModalForEdit(acc) {
  editingAccount.value = acc;
  showFormModal.value = true;
}

function onAccountSaved() {
  showFormModal.value = false;
  load();
}

function startDelete(acc) {
  accountToDelete.value = acc;
  showDeleteModal.value = true;
}

async function confirmDelete() {
  const acc = accountToDelete.value;
  if (!acc) return;
  deleting.value = true;
  try {
    await FinancialV2.bankAccounts.destroy(acc.id);
    notifySuccess('Conta removida.');
    showDeleteModal.value = false;
    accountToDelete.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao remover');
  } finally {
    deleting.value = false;
  }
}

// Ordenação: ativas primeiro, depois inativas
const sortedAccounts = computed(() => {
  return [...accounts.value].sort((a, b) => {
    if (a.active !== b.active) return a.active ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
});
</script>

<template>
  <div class="bank-tab">
    <header class="bank-tab__header">
      <div>
        <h2 class="bank-tab__title">Contas Bancárias e Caixas</h2>
        <p class="bank-tab__subtitle">Setup #4 · Onde o dinheiro entra e sai</p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Adicionar"
        class="finv2-btn-icon-only-mobile"
        @click="openModalForNew"
      />
    </header>

    <!-- KPIs -->
    <div class="bank-tab__kpis">
      <div class="bank-tab__kpi bank-tab__kpi--accent-emerald">
        <span class="bank-tab__kpi-label">Contas Ativas</span>
        <strong class="bank-tab__kpi-value">{{ summary.active_count }}</strong>
        <span class="bank-tab__kpi-hint">de {{ summary.total_count }} totais</span>
      </div>
      <div class="bank-tab__kpi bank-tab__kpi--accent-teal">
        <span class="bank-tab__kpi-label">Saldo Inicial Total</span>
        <strong class="bank-tab__kpi-value">{{ centsToBRLShort(summary.initial_balance_total_cents) }}</strong>
      </div>
      <div class="bank-tab__kpi bank-tab__kpi--accent-blue">
        <span class="bank-tab__kpi-label">Saldo Estimado Atual</span>
        <strong class="bank-tab__kpi-value">{{ centsToBRLShort(summary.estimated_balance_total_cents) }}</strong>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading && accounts.length === 0" class="bank-tab__state">
      <div class="bank-tab__spinner" />
      <span>Carregando contas...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="bank-tab__state bank-tab__state--error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="accounts.length === 0" class="bank-tab__state bank-tab__state--empty">
      <i class="i-lucide-landmark" />
      <h3>Nenhuma conta cadastrada</h3>
      <p>Cadastre pelo menos 1 conta + 1 caixa físico para usar o módulo.</p>
      <BeclinicButton variant="solid" color="blue" icon="i-lucide-plus" label="Adicionar primeira" @click="openModalForNew" />
    </div>

    <!-- Tabela -->
    <div v-else class="bank-tab__table-wrap">
      <table class="bank-tab__table">
        <thead>
          <tr>
            <th class="bank-tab__th-color"></th>
            <th class="bank-tab__th-name">APELIDO</th>
            <th class="bank-tab__th-bank">BANCO / TIPO</th>
            <th class="bank-tab__th-acc">AGÊNCIA / CONTA</th>
            <th class="bank-tab__th-balance">SALDO INICIAL</th>
            <th class="bank-tab__th-default">PADRÃO</th>
            <th class="bank-tab__th-status">STATUS</th>
            <th class="bank-tab__th-actions"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="acc in sortedAccounts" :key="acc.id" :class="{ 'bank-tab__row--inactive': !acc.active }">
            <td class="bank-tab__td-color">
              <!-- Ícone + swatch combinados (1.8.0.13): ícone do tipo
                   (landmark/wallet/credit-card) sobre fundo na cor da conta.
                   Substitui o quadradinho de cor puro — mais informativo
                   visualmente (operador identifica "Caixa físico" só pelo ícone). -->
              <span
                class="bank-tab__icon-swatch"
                :style="{ background: acc.color || '#3b82f6' }"
              >
                <i :class="kindIcon(acc.kind)" />
              </span>
            </td>
            <td class="bank-tab__td-name">
              <strong>{{ acc.name }}</strong>
            </td>
            <td class="bank-tab__td-bank">
              <div class="bank-tab__bank-line">{{ acc.bank_name || '—' }}</div>
              <div class="bank-tab__bank-sub">{{ kindLabel(acc.kind) }}</div>
            </td>
            <td class="bank-tab__td-acc">{{ agencyAccount(acc) }}</td>
            <td class="bank-tab__td-balance">{{ centsToBRL(acc.initial_balance_cents) }}</td>
            <td class="bank-tab__td-default">
              <div class="bank-tab__badges">
                <span v-if="acc.default_for_receivables" class="bank-tab__badge bank-tab__badge--receb">RECEB</span>
                <span v-if="acc.default_for_payments" class="bank-tab__badge bank-tab__badge--pgto">PGTO</span>
                <span v-if="!acc.default_for_receivables && !acc.default_for_payments" class="bank-tab__badges-empty">—</span>
              </div>
            </td>
            <td class="bank-tab__td-status" @click.stop>
              <!-- Toggle inline (1.8.0.13): mesmo padrão de Formas de Pagamento.
                   1 clique ativa/inativa sem modal — UX consistente nas 2 telas
                   de setup financeiro. Azul=on, cinza=off (Toggle global). -->
              <Toggle
                :model-value="acc.active"
                size="sm"
                @update:model-value="(v) => onToggleStatus(acc, v)"
              />
            </td>
            <td class="bank-tab__td-actions" @click.stop>
              <div class="bank-tab__actions-group">
                <!-- position="left" pra evitar overflow horizontal — botões
                     estão na borda direita da tabela, tooltip "top" centrado
                     vazaria pro lado direito da viewport. `multiline` reforça
                     wrap caso texto cresça no futuro. -->
                <Tooltip label="Editar" position="left">
                  <button
                    type="button"
                    class="bank-tab__icon-btn"
                    aria-label="Editar"
                    @click.stop="openModalForEdit(acc)"
                  >
                    <i class="i-lucide-pencil" />
                  </button>
                </Tooltip>
                <!-- Excluir = soft-delete; backend rejeita se saldo != 0 ou
                     houver vínculos. Mensagem orienta a transferir antes. -->
                <Tooltip
                  label="Excluir (apenas se saldo zerado)"
                  position="left"
                  multiline
                >
                  <button
                    type="button"
                    class="bank-tab__icon-btn bank-tab__icon-btn--danger"
                    aria-label="Excluir"
                    @click.stop="startDelete(acc)"
                  >
                    <i class="i-lucide-trash-2" />
                  </button>
                </Tooltip>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <BankAccountFormModalV2
      v-if="showFormModal"
      :show="showFormModal"
      :existing-account="editingAccount"
      :existing-accounts="accounts"
      @close="showFormModal = false"
      @confirm="onAccountSaved"
    />

    <ConfirmDangerModalV2
      v-if="showDeleteModal"
      :show="showDeleteModal"
      title="Remover conta?"
      confirm-label="Sim, remover"
      tone="danger"
      :loading="deleting"
      @close="showDeleteModal = false; accountToDelete = null"
      @confirm="confirmDelete"
    >
      A conta <strong>{{ accountToDelete?.name }}</strong> será removida.
      <br>
      Só é permitido se o saldo atual estiver <strong>zerado</strong>. Caso contrário,
      transfira o saldo antes via "Sangria/Suprimento".
    </ConfirmDangerModalV2>
  </div>
</template>

<style scoped lang="scss">
.bank-tab { color: rgb(var(--slate-12)); }

.bank-tab__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 16px; margin-bottom: 20px;
  padding-bottom: 16px; border-bottom: 1px solid rgb(var(--slate-4));
}
.bank-tab__title { margin: 0 0 4px; font-size: 22px; font-weight: 700; }
.bank-tab__subtitle { margin: 0; font-size: 13px; color: rgb(var(--slate-10)); }

/* ── KPIs ────────────────────────────────────────────────── */
.bank-tab__kpis {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 20px;

  @media (max-width: 720px) { grid-template-columns: 1fr; }
}

.bank-tab__kpi {
  position: relative;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 18px 16px 14px;
  display: flex; flex-direction: column; gap: 4px;
  overflow: hidden;

  /* Faixa colorida no topo do card (mesmo visual do wireframe). */
  &::before {
    content: '';
    position: absolute; top: 0; left: 0; right: 0; height: 3px;
    background: rgb(var(--slate-6));
  }
  &--accent-emerald::before { background: linear-gradient(90deg, rgb(var(--emerald-9)), rgb(var(--emerald-7))); }
  &--accent-teal::before    { background: linear-gradient(90deg, rgb(var(--teal-9)),    rgb(var(--teal-7))); }
  &--accent-blue::before    { background: linear-gradient(90deg, rgb(var(--blue-9)),    rgb(var(--blue-7))); }
}

.bank-tab__kpi-label {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: rgb(var(--slate-9));
}

.bank-tab__kpi-value {
  font-size: 26px;
  font-weight: 700;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
}

.bank-tab__kpi-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* ── States ──────────────────────────────────────────────── */
.bank-tab__state {
  display: flex; align-items: center; justify-content: center;
  padding: 60px 24px; text-align: center;
  color: rgb(var(--slate-9));
  font-size: 14px; gap: 12px;
}
.bank-tab__state--empty, .bank-tab__state--error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.bank-tab__state--error { color: rgb(var(--ruby-10)); }

.bank-tab__spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── Table ───────────────────────────────────────────────── */
.bank-tab__table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.bank-tab__table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 900px;

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 10px 12px;
      text-align: left;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
      border-bottom: 1px solid rgb(var(--slate-4));
      white-space: nowrap;
    }
  }

  tbody {
    tr {
      border-bottom: 1px solid rgb(var(--slate-3));
      transition: background-color .12s ease;
      &:last-child { border-bottom: 0; }
      &:hover { background: rgba(255, 255, 255, 0.02); }
      &.bank-tab__row--inactive { opacity: 0.55; }
    }
    td { padding: 12px; vertical-align: middle; }
  }
}

.bank-tab__th-color, .bank-tab__td-color { width: 44px; padding-right: 8px !important; }
.bank-tab__th-name, .bank-tab__td-name { min-width: 200px; }
.bank-tab__th-bank, .bank-tab__td-bank { min-width: 140px; }
.bank-tab__th-acc, .bank-tab__td-acc { width: 160px; font-variant-numeric: tabular-nums; color: rgb(var(--slate-10)); }
.bank-tab__th-balance, .bank-tab__td-balance {
  width: 140px; text-align: right; font-variant-numeric: tabular-nums;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.bank-tab__th-default, .bank-tab__td-default { width: 130px; }
.bank-tab__th-status, .bank-tab__td-status { width: 70px; white-space: nowrap; }
.bank-tab__th-actions, .bank-tab__td-actions { width: 1%; white-space: nowrap; text-align: right; }

/* Ícone + cor da conta (substitui o swatch puro de 14px).
   Quadrado 28px com bordas suaves + ícone branco centralizado.
   Cor de fundo vem do `acc.color` (paleta de cores escolhida no modal). */
.bank-tab__icon-swatch {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px; height: 28px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.15);

  i { color: rgba(255, 255, 255, 0.95); width: 14px; height: 14px; }
}

.bank-tab__bank-line { font-weight: 500; color: rgb(var(--slate-12)); }
.bank-tab__bank-sub { font-size: 11px; color: rgb(var(--slate-9)); }

.bank-tab__badges {
  display: inline-flex; gap: 6px; align-items: center;
}
.bank-tab__badge {
  display: inline-block;
  padding: 2px 7px;
  border-radius: 5px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.05em;

  &--receb {
    background: rgba(16, 185, 129, 0.12);
    color: rgb(var(--emerald-11));
  }
  &--pgto {
    background: rgba(59, 130, 246, 0.12);
    color: rgb(var(--blue-11));
  }
}
.bank-tab__badges-empty {
  color: rgb(var(--slate-8));
  font-size: 11px;
}

/* .bank-tab__status (badge ATIVA/INATIVA) removido 1.8.0.13 — Toggle inline
   substituiu o badge, mesmo padrão de SettingsPaymentMethodsTab. */

/* Ações em ícones (substitui botões "Editar"/"Inativar" texto).
   Mesma régua de .pmtab-icon-btn em Formas de Pagamento — visual unificado. */
.bank-tab__actions-group {
  display: inline-flex;
  gap: 4px;
  align-items: center;
}
.bank-tab__icon-btn {
  width: 28px; height: 28px;
  padding: 0;
  margin: 0;
  display: inline-flex; align-items: center; justify-content: center;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
  i { width: 14px; height: 14px; }

  &:hover {
    background: rgb(var(--slate-3));
    color: rgb(var(--blue-11));
    border-color: rgb(var(--slate-4));
  }

  /* Variante danger — vermelho POR PADRÃO (não só hover) pra sinalizar
     ação destrutiva. Hover intensifica com background vermelho sutil.
     IMPORTANTE: projeto usa --ruby-N (Radix), NÃO --red-N. Tokens --red-*
     são undefined → vira cor inválida → fallback preto (perde o vermelho).
     Validado em app/javascript/dashboard/assets/scss/_next-colors.scss. */
  &--danger {
    color: rgb(var(--ruby-11));
  }
  &--danger:hover {
    background: rgb(var(--ruby-3));
    color: rgb(var(--ruby-11));
    border-color: rgb(var(--ruby-7));
  }
}
</style>
