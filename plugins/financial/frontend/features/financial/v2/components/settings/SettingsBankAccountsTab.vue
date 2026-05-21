<script setup>
/**
 * Aba Contas Bancárias e Caixa — CRUD básico (canon §4.2).
 * Tipos: checking | savings | cash | card_receivable.
 * Saldo inicial editável só na criação. Saldo atual sempre calculado.
 *
 * UI premium: FormSelect, Checkbox, BeclinicButton, Badge, formatter live.
 */
import { ref, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FinancialV2 from '../../api/financialV2';
import {
  brlInputToCents,
  centsToBRL,
  centsToInputString,
  formatCurrencyInput,
} from '../../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const accounts = ref([]);
const loading = ref(false);
const showForm = ref(false);
const formMode = ref('create');
const form = ref(emptyForm());

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const KIND_OPTIONS = [
  { value: 'checking',         label: 'Conta corrente' },
  { value: 'savings',          label: 'Poupança' },
  { value: 'cash',             label: 'Caixa físico' },
  { value: 'card_receivable',  label: 'A receber de maquininha' },
];

const KIND_LABEL = Object.fromEntries(KIND_OPTIONS.map(k => [k.value, k.label]));

const KIND_BADGE = {
  checking:        { color: 'blue',    icon: 'i-lucide-building-2',    label: 'Corrente' },
  savings:         { color: 'emerald', icon: 'i-lucide-piggy-bank',    label: 'Poupança' },
  cash:            { color: 'amber',   icon: 'i-lucide-banknote',      label: 'Caixa' },
  card_receivable: { color: 'violet',  icon: 'i-lucide-credit-card',   label: 'Maquininha' },
};

function kindBadge(kind) {
  return KIND_BADGE[kind] || { color: 'slate', icon: 'i-lucide-circle', label: kind };
}

function emptyForm() {
  return {
    id: null,
    name: '',
    kind: 'checking',
    initial_balance_str: '0,00',
    card_settlement_days: 1,
    active: true,
  };
}

async function load() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.bankAccounts.index();
    accounts.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar contas');
  } finally {
    loading.value = false;
  }
}

function startCreate() {
  form.value = emptyForm();
  formMode.value = 'create';
  showForm.value = true;
}

function startEdit(acc) {
  form.value = {
    id: acc.id,
    name: acc.name,
    kind: acc.kind,
    initial_balance_str: centsToInputString(acc.initial_balance_cents),
    card_settlement_days: acc.card_settlement_days || 1,
    active: acc.active,
  };
  formMode.value = 'edit';
  showForm.value = true;
}

function onInitialBalanceInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value.initial_balance_str = formatted;
  e.target.value = formatted;
}

async function save() {
  if (!form.value.name?.trim()) {
    notifyError('Informe um nome para a conta.');
    return;
  }
  loading.value = true;
  try {
    const payload = {
      bank_account: {
        name: form.value.name,
        kind: form.value.kind,
        active: form.value.active,
        card_settlement_days: form.value.kind === 'card_receivable'
          ? form.value.card_settlement_days
          : null,
      },
    };
    if (formMode.value === 'create') {
      payload.bank_account.initial_balance_cents = brlInputToCents(
        form.value.initial_balance_str || '0,00'
      );
      await FinancialV2.bankAccounts.create(payload);
      notifySuccess('Conta criada.');
    } else {
      await FinancialV2.bankAccounts.update(form.value.id, payload);
      notifySuccess('Conta atualizada.');
    }
    showForm.value = false;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao salvar conta');
  } finally {
    loading.value = false;
  }
}

// Estado do ConfirmDangerModal (regra do projeto: usar modal pra exclusões).
const showDeleteModal = ref(false);
const accountToDelete = ref(null);
const deleting = ref(false);

function destroy(acc) {
  accountToDelete.value = acc;
  showDeleteModal.value = true;
}

async function confirmDestroy() {
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
    notifyError(err?.response?.data?.message || err?.response?.data?.errors?.join('; ') || 'Erro ao remover');
  } finally {
    deleting.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="set-bank">
    <header class="set-bank__header">
      <div class="set-bank__header-text">
        <h2 class="set-bank__title">Contas e Caixa</h2>
        <p class="set-bank__subtitle">
          Onde o dinheiro fica — conta corrente PJ, caixa físico, conta de maquininha.
          O caixa físico é obrigatório para abrir sessão diária.
        </p>
      </div>
      <BeclinicButton
        v-if="!showForm"
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Nova conta"
        @click="startCreate"
      />
    </header>

    <!-- Form de criar/editar -->
    <div v-if="showForm" class="set-bank__form">
      <h3 class="set-bank__form-title">
        <i :class="formMode === 'create' ? 'i-lucide-plus' : 'i-lucide-pencil'" class="w-4 h-4" />
        {{ formMode === 'create' ? 'Nova conta' : 'Editar conta' }}
      </h3>

      <div class="set-bank__form-grid">
        <label class="set-bank__field set-bank__field--span-2">
          <span class="set-bank__field-label">Nome</span>
          <input
            v-model="form.name"
            type="text"
            class="finv2-input"
            placeholder="Ex.: Itaú PJ, Caixa da Recepção"
          />
        </label>

        <label class="set-bank__field">
          <span class="set-bank__field-label">Tipo</span>
          <FormSelect v-model="form.kind" :options="KIND_OPTIONS" />
        </label>

        <label v-if="formMode === 'create'" class="set-bank__field">
          <span class="set-bank__field-label">Saldo inicial</span>
          <div class="set-bank__currency-wrap">
            <span class="set-bank__currency-prefix">R$</span>
            <input
              :value="form.initial_balance_str"
              type="text"
              inputmode="numeric"
              placeholder="0,00"
              class="finv2-input set-bank__currency-input"
              @input="onInitialBalanceInput"
            />
          </div>
        </label>

        <label v-if="form.kind === 'card_receivable'" class="set-bank__field">
          <span class="set-bank__field-label">D + N (dias até liquidação)</span>
          <input
            v-model.number="form.card_settlement_days"
            type="number"
            min="1"
            max="90"
            class="finv2-input"
          />
        </label>

        <div class="set-bank__field set-bank__field--span-2">
          <Checkbox v-model="form.active" label="Conta ativa" />
        </div>
      </div>

      <div class="set-bank__form-actions">
        <BeclinicButton
          variant="ghost"
          color="slate"
          label="Cancelar"
          :disabled="loading"
          @click="showForm = false"
        />
        <BeclinicButton
          variant="solid"
          color="teal"
          icon="i-lucide-check"
          label="Salvar conta"
          :is-loading="loading"
          :disabled="loading"
          @click="save"
        />
      </div>
    </div>

    <!-- Listagem -->
    <div v-if="loading && !showForm" class="finv2-state">
      <div class="finv2-spinner" />
      <span>Carregando contas…</span>
    </div>
    <div v-else-if="accounts.length" class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Nome</th>
            <th>Tipo</th>
            <th class="finv2-table__th-num">Saldo inicial</th>
            <th>Status</th>
            <th class="finv2-table__th-actions">Ações</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="acc in accounts" :key="acc.id" :class="{ 'set-bank__row--inactive': !acc.active }">
            <td><strong>{{ acc.name }}</strong></td>
            <td>
              <Badge
                :label="kindBadge(acc.kind).label"
                :color="kindBadge(acc.kind).color"
                :icon="kindBadge(acc.kind).icon"
                size="xs"
              />
              <small v-if="acc.card_settlement_days" class="set-bank__settlement"> · D+{{ acc.card_settlement_days }}</small>
            </td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">
              {{ centsToBRL(acc.initial_balance_cents) }}
            </td>
            <td>
              <Badge
                :label="acc.active ? 'Ativa' : 'Inativa'"
                :color="acc.active ? 'emerald' : 'slate'"
                :icon="acc.active ? 'i-lucide-check-circle-2' : 'i-lucide-circle-off'"
                size="xs"
              />
            </td>
            <td class="finv2-table__td-actions">
              <BeclinicButton size="xs" variant="ghost" color="slate" icon="i-lucide-pencil" @click="startEdit(acc)" />
              <BeclinicButton size="xs" variant="ghost" color="ruby"  icon="i-lucide-trash-2" @click="destroy(acc)" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-else-if="!loading" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-wallet w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma conta cadastrada</p>
      <p class="finv2-state__hint">Cadastre pelo menos 1 conta + 1 caixa físico para usar o módulo.</p>
    </div>

    <!-- Confirmação de exclusão de conta. -->
    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      title="Excluir conta?"
      :message="accountToDelete
        ? `A conta '${accountToDelete.name}' será removida. Só é permitido se o saldo estiver zerado — caso contrário, o backend recusa a operação.`
        : ''"
      confirm-label="Excluir conta"
      :loading="deleting"
      @confirm="confirmDestroy"
    />
  </div>
</template>

<style scoped lang="scss">
.set-bank__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 16px; margin-bottom: 18px; flex-wrap: wrap;
}
.set-bank__title { margin: 0 0 4px; font-size: 17px; font-weight: 600; color: rgb(var(--slate-12)); }
.set-bank__subtitle { margin: 0; color: rgb(var(--slate-9)); font-size: 13px; line-height: 1.5; max-width: 520px; }

/* Form */
.set-bank__form {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--blue-6));
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 16px;
}
.set-bank__form-title {
  margin: 0 0 14px;
  font-size: 13px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: inline-flex; align-items: center; gap: 6px;
  text-transform: uppercase; letter-spacing: 0.04em;
  i { color: rgb(var(--blue-9)); }
}
.set-bank__form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 640px) {
  .set-bank__form-grid { grid-template-columns: 1fr; }
}
.set-bank__field { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.set-bank__field--span-2 { grid-column: 1 / -1; }
.set-bank__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
}
.set-bank__form-actions {
  display: flex; justify-content: flex-end; gap: 8px; margin-top: 14px;
  padding-top: 14px; border-top: 1px solid rgb(var(--slate-4));
}

/* Currency input */
.set-bank__currency-wrap { position: relative; display: flex; align-items: center; }
.set-bank__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.set-bank__currency-input {
  padding-left: 32px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

.set-bank__row--inactive { opacity: 0.55; }
.set-bank__settlement { color: rgb(var(--slate-9)); font-size: 11px; }
</style>
