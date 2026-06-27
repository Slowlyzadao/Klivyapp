<script setup>
/**
 * Modal de criar/editar Conta Bancária ou Caixa — wireframe Setup #4.
 *
 * Campos:
 *   - Apelido* (name)              Banco (bank_name)
 *   - Agência                      Conta-dígito (account_number)
 *   - Tipo* (kind FormSelect)      CNPJ
 *   - Chave PIX                    Saldo Inicial* (currency, só na criação)
 *   - Data de Corte* (DatePickerBR — referência de fatura/extrato)
 *   - Cor (paleta canon 8 cores)
 *   - Status (Ativa/Inativa)
 *   - Toggle "Padrão de Recebimento" e "Padrão de Pagamento"
 *
 * Endpoints:
 *   POST   /financial/v2/bank_accounts
 *   PATCH  /financial/v2/bank_accounts/:id   (sem permitir mudança de saldo inicial)
 */
import { ref, computed, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../../api/financialV2';

const props = defineProps({
  show: { type: Boolean, default: false },
  existingAccount: { type: Object, default: null },
  existingAccounts: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// ── Canon dos campos enumeráveis ─────────────────────────────────────
const KIND_OPTIONS = [
  { value: 'checking',        label: 'Conta corrente' },
  { value: 'savings',         label: 'Poupança' },
  { value: 'cash',            label: 'Caixa físico' },
  { value: 'card_receivable', label: 'A receber de maquininha' },
];

const STATUS_OPTIONS = [
  { value: true,  label: 'Ativa' },
  { value: false, label: 'Inativa' },
];

// Paleta canon (consistência com badges/avatares do design system Klivy).
const COLOR_PALETTE = [
  { value: '#10b981', label: 'Emerald' },
  { value: '#14b8a6', label: 'Teal' },
  { value: '#3b82f6', label: 'Blue' },
  { value: '#8b5cf6', label: 'Violet' },
  { value: '#ec4899', label: 'Pink' },
  { value: '#f59e0b', label: 'Amber' },
  { value: '#ef4444', label: 'Red' },
  { value: '#64748b', label: 'Slate' },
];

// ── Form state ───────────────────────────────────────────────────────
const form = ref(emptyForm());
const submitting = ref(false);

const isEdit = computed(() => !!props.existingAccount);

function emptyForm() {
  return {
    name: '',
    bank_name: '',
    agency: '',
    account_number: '',
    kind: 'checking',
    cnpj: '',
    pix_key: '',
    initial_balance_str: '0,00',
    cut_date: '',
    color: '#3b82f6',
    active: true,
    default_for_receivables: false,
    default_for_payments: false,
    card_settlement_days: 1,
  };
}

// Conversões cents/R$
function centsToInputString(cents) {
  if (cents == null) return '0,00';
  return (cents / 100).toFixed(2).replace('.', ',');
}

function brlInputToCents(text) {
  if (!text) return 0;
  const normalized = String(text).trim().replace(/\./g, '').replace(',', '.');
  const f = parseFloat(normalized);
  return Number.isFinite(f) ? Math.round(f * 100) : 0;
}

function formatCurrencyInput(text) {
  // Aceita "1234,5" / "1234.5" / "1.234,56" — devolve "1.234,56"
  if (!text) return '0,00';
  const digitsOnly = String(text).replace(/[^\d]/g, '');
  if (!digitsOnly) return '0,00';
  const cents = parseInt(digitsOnly, 10);
  const reais = Math.floor(cents / 100);
  const cs = (cents % 100).toString().padStart(2, '0');
  return reais.toLocaleString('pt-BR') + ',' + cs;
}

function onInitialBalanceInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value.initial_balance_str = formatted;
  e.target.value = formatted;
}

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;
    if (props.existingAccount) {
      const a = props.existingAccount;
      form.value = {
        name: a.name || '',
        bank_name: a.bank_name || '',
        agency: a.agency || '',
        account_number: a.account_number || '',
        kind: a.kind || 'checking',
        cnpj: a.cnpj || '',
        pix_key: a.pix_key || '',
        initial_balance_str: centsToInputString(a.initial_balance_cents),
        cut_date: a.cut_date || '',
        color: a.color || '#3b82f6',
        active: a.active !== false,
        default_for_receivables: !!a.default_for_receivables,
        default_for_payments: !!a.default_for_payments,
        card_settlement_days: a.card_settlement_days || 1,
      };
    } else {
      form.value = emptyForm();
    }
  },
  { immediate: true },
);

// Quem já tem o badge de default na conta? Pra avisar o operador
// que ativar aqui vai TIRAR de lá (constraint de unicidade).
const currentDefaultReceiverName = computed(() => {
  const found = props.existingAccounts.find(
    a => a.default_for_receivables && a.id !== props.existingAccount?.id
  );
  return found?.name || null;
});

const currentDefaultPayerName = computed(() => {
  const found = props.existingAccounts.find(
    a => a.default_for_payments && a.id !== props.existingAccount?.id
  );
  return found?.name || null;
});

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.name?.trim()) return false;
  if (!form.value.kind) return false;
  // cut_date obrigatório no wireframe — exceto pra caixa físico (não tem extrato)
  if (form.value.kind !== 'cash' && !form.value.cut_date) return false;
  return true;
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      bank_account: {
        name: form.value.name.trim(),
        bank_name: form.value.bank_name?.trim() || null,
        agency: form.value.agency?.trim() || null,
        account_number: form.value.account_number?.trim() || null,
        kind: form.value.kind,
        cnpj: form.value.cnpj?.trim() || null,
        pix_key: form.value.pix_key?.trim() || null,
        cut_date: form.value.cut_date || null,
        color: form.value.color || '#3b82f6',
        active: form.value.active,
        default_for_receivables: form.value.default_for_receivables,
        default_for_payments: form.value.default_for_payments,
        card_settlement_days: form.value.kind === 'card_receivable'
          ? (form.value.card_settlement_days || 1)
          : null,
      },
    };
    if (!isEdit.value) {
      payload.bank_account.initial_balance_cents = brlInputToCents(form.value.initial_balance_str || '0,00');
    }
    if (isEdit.value) {
      // Saldo inicial é frozen após criação — não envia.
      delete payload.bank_account.initial_balance_cents;
      await FinancialV2.bankAccounts.update(props.existingAccount.id, payload);
      notifySuccess('Conta atualizada.');
    } else {
      await FinancialV2.bankAccounts.create(payload);
      notifySuccess('Conta criada.');
    }
    emit('confirm');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || err?.response?.data?.message || 'Erro ao salvar conta');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const titleText = computed(() => isEdit.value ? `Editar — ${props.existingAccount?.name}` : 'Nova Conta');

// Esconde campos bancários quando é caixa físico (não faz sentido)
const isCash = computed(() => form.value.kind === 'cash');
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="bam-v2__backdrop">
      <div class="bam-v2__modal" role="dialog" aria-modal="true">
        <header class="bam-v2__header">
          <div>
            <h2 class="bam-v2__title">
              <i class="i-lucide-landmark bam-v2__title-icon" />
              {{ titleText }}
            </h2>
          </div>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="bam-v2__body">
          <div class="bam-v2__row">
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Apelido <span class="bam-v2__required">*</span></span>
              <input v-model="form.name" type="text" class="finv2-input" placeholder="Ex.: Itaú PJ, Caixa Recepção" maxlength="120" />
            </label>
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Banco</span>
              <input v-model="form.bank_name" :disabled="isCash" type="text" class="finv2-input" placeholder="Ex.: Itaú, Sicredi" maxlength="120" />
            </label>
          </div>

          <div v-if="!isCash" class="bam-v2__row">
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Agência</span>
              <input v-model="form.agency" type="text" class="finv2-input" placeholder="0001" maxlength="20" />
            </label>
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Conta-dígito</span>
              <input v-model="form.account_number" type="text" class="finv2-input" placeholder="12345-6" maxlength="30" />
            </label>
          </div>

          <div class="bam-v2__row">
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Tipo <span class="bam-v2__required">*</span></span>
              <FormSelect v-model="form.kind" :options="KIND_OPTIONS" />
            </label>
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">CNPJ</span>
              <input v-model="form.cnpj" :disabled="isCash" type="text" class="finv2-input" placeholder="00.000.000/0000-00" maxlength="20" />
            </label>
          </div>

          <div class="bam-v2__row">
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Chave PIX</span>
              <input v-model="form.pix_key" :disabled="isCash" type="text" class="finv2-input" placeholder="CPF/email/telefone/chave aleatória" maxlength="120" />
            </label>
            <label v-if="!isEdit" class="bam-v2__field">
              <span class="bam-v2__field-label">Saldo Inicial <span class="bam-v2__required">*</span></span>
              <div class="bam-v2__currency-wrap">
                <span class="bam-v2__currency-prefix">R$</span>
                <input
                  :value="form.initial_balance_str"
                  type="text"
                  inputmode="numeric"
                  placeholder="0,00"
                  class="finv2-input bam-v2__currency-input"
                  @input="onInitialBalanceInput"
                />
              </div>
            </label>
            <div v-else class="bam-v2__field">
              <span class="bam-v2__field-label">Saldo Inicial</span>
              <div class="bam-v2__readonly">
                R$ {{ centsToInputString(existingAccount?.initial_balance_cents) }}
                <span class="bam-v2__field-hint-mini">(imutável após criação)</span>
              </div>
            </div>
          </div>

          <div class="bam-v2__row">
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">
                Data de Corte
                <span v-if="!isCash" class="bam-v2__required">*</span>
              </span>
              <DatePickerBR v-model="form.cut_date" placeholder="DD/MM/AAAA" :disabled="isCash" />
              <span class="bam-v2__field-hint-mini">
                {{ isCash ? 'Não aplicável a caixa físico' : 'Dia de referência pra extrato/fatura' }}
              </span>
            </label>
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">Status</span>
              <FormSelect v-model="form.active" :options="STATUS_OPTIONS" />
            </label>
          </div>

          <div v-if="form.kind === 'card_receivable'" class="bam-v2__row">
            <label class="bam-v2__field">
              <span class="bam-v2__field-label">D + N (dias até liquidação)</span>
              <input v-model.number="form.card_settlement_days" type="number" min="1" max="90" class="finv2-input" />
              <span class="bam-v2__field-hint-mini">Quantos dias entre venda e crédito do valor</span>
            </label>
          </div>

          <!-- Cor (paleta) -->
          <div class="bam-v2__field">
            <span class="bam-v2__field-label">Cor</span>
            <div class="bam-v2__color-palette">
              <button
                v-for="opt in COLOR_PALETTE"
                :key="opt.value"
                type="button"
                class="bam-v2__color-chip"
                :class="{ 'bam-v2__color-chip--selected': form.color === opt.value }"
                :style="{ background: opt.value }"
                :title="opt.label"
                @click="form.color = opt.value"
              >
                <i v-if="form.color === opt.value" class="i-lucide-check" />
              </button>
            </div>
          </div>

          <!-- Defaults -->
          <div class="bam-v2__defaults">
            <div class="bam-v2__default-row">
              <Checkbox v-model="form.default_for_receivables">
                <span>Conta padrão de <strong>recebimento</strong></span>
              </Checkbox>
              <span v-if="form.default_for_receivables && currentDefaultReceiverName" class="bam-v2__default-warn">
                <i class="i-lucide-info" /> Vai remover o padrão de
                <strong>{{ currentDefaultReceiverName }}</strong>
              </span>
            </div>
            <div class="bam-v2__default-row">
              <Checkbox v-model="form.default_for_payments" :disabled="form.kind === 'cash'">
                <span>
                  Conta padrão de <strong>pagamento</strong>
                  <span v-if="form.kind === 'cash'" class="bam-v2__field-hint-mini">(caixa não paga fornecedor)</span>
                </span>
              </Checkbox>
              <span v-if="form.default_for_payments && currentDefaultPayerName" class="bam-v2__default-warn">
                <i class="i-lucide-info" /> Vai remover o padrão de
                <strong>{{ currentDefaultPayerName }}</strong>
              </span>
            </div>
          </div>
        </div>

        <footer class="bam-v2__footer">
          <BeclinicButton variant="ghost" color="slate" label="Cancelar" :disabled="submitting" @click="close" />
          <BeclinicButton
            variant="solid"
            color="blue"
            icon="i-lucide-check"
            :label="isEdit ? 'Salvar alterações' : 'Salvar'"
            :is-loading="submitting"
            :disabled="!validForSubmit"
            @click="submit"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
.bam-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .bam-v2__backdrop { align-items: center; padding: 16px; }
}

.bam-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .bam-v2__modal {
    width: min(620px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.bam-v2__header {
  display: flex; justify-content: space-between; align-items: center;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.bam-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.bam-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--emerald-9)); }

.bam-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.bam-v2__row {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }
}

.bam-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.bam-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.bam-v2__required { color: rgb(var(--ruby-9)); }
.bam-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-weight: 400;
  font-style: italic;
}

.bam-v2__readonly {
  padding: 8px 12px;
  background: rgb(var(--slate-3));
  border-radius: 6px;
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-11));
  display: flex; gap: 8px; align-items: center;
}

/* Currency input */
.bam-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.bam-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.bam-v2__currency-input {
  padding-left: 32px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

/* Color palette */
.bam-v2__color-palette {
  display: flex; gap: 8px; flex-wrap: wrap;
  padding: 4px 0;
}
.bam-v2__color-chip {
  width: 28px; height: 28px;
  padding: 0;                        /* <button> default vem com padding */
  margin: 0;
  border-radius: 8px;
  border: 2px solid transparent;
  cursor: pointer;
  display: inline-flex; align-items: center; justify-content: center;
  transition: transform 0.1s ease, border-color 0.12s ease;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);

  &:hover { transform: scale(1.08); }
  &--selected {
    border-color: rgb(var(--slate-12));
    box-shadow: 0 0 0 2px rgb(var(--slate-1)), 0 0 0 4px rgb(var(--slate-7));
  }

  /* Ícone de seleção (i-lucide-check) — dimensões explícitas + display block
     pra que o background-image do iconify renderize visível. `color: white`
     define a cor do mask. */
  i {
    display: block;
    width: 14px;
    height: 14px;
    color: white;
    flex-shrink: 0;
  }
}

/* Defaults */
.bam-v2__defaults {
  display: flex; flex-direction: column; gap: 10px;
  padding: 12px 14px;
  background: rgb(var(--slate-2));
  border-radius: 8px;
  border-left: 3px solid rgb(var(--blue-7));
}
.bam-v2__default-row {
  display: flex; flex-direction: column; gap: 4px;
}
.bam-v2__default-warn {
  display: inline-flex; align-items: center; gap: 6px;
  font-size: 11px;
  color: rgb(var(--amber-11));
  padding-left: 26px;
  i { width: 12px; height: 12px; }
  strong { color: rgb(var(--slate-12)); }
}

.bam-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
