<script setup>
/**
 * Transferência interna entre contas bancárias — canon §4.2 + CT-CC-03.
 *
 * Cria 2 `Financial::Entry` via service `TransferBetweenAccounts`:
 *   - direction=out + kind=transferencia na conta ORIGEM
 *   - direction=in  + kind=transferencia na conta DESTINO
 *   - affects_dre=false (movimento NEUTRO no DRE — não conta como receita/despesa)
 *   - affects_cashflow=true (aparece no Fluxo de Caixa)
 *   - transfer_pair_id liga as duas pra rastreabilidade
 *
 * Validações backend (já cobertas pelo service):
 *   - amount > 0
 *   - contas diferentes
 *   - saldo suficiente na origem
 *
 * Role obrigatório: GERENTE ou ADMIN.
 *
 * Props:
 *   - show: Boolean
 *
 * Eventos:
 *   - close
 *   - confirm: { entry_in, entry_out } (retorno do backend)
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../api/financialV2';
import { brlInputToCents, formatCurrencyInput, centsToBRL, bankKindLabel } from '../composables/useMoney';

const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// ── Estado do form ──────────────────────────────────────────────
const occurredAt = ref(new Date().toISOString().slice(0, 10));
const fromAccountId = ref(null);
const toAccountId = ref(null);
const amountStr = ref('');
const notes = ref('');
const submitting = ref(false);

const bankAccounts = ref([]);

const bankAccountOptions = computed(() =>
  bankAccounts.value.map(b => ({
    value: b.id,
    label: `${b.name} · ${bankKindLabel(b.kind)}`,
    hint: b.current_balance_cents != null ? centsToBRL(b.current_balance_cents) : null,
  })),
);

// Destino remove a origem da lista pra evitar contas iguais (validação
// também no backend, mas guarda no front evita pre-validation noise).
const toAccountOptions = computed(() =>
  bankAccountOptions.value.filter(o => o.value !== fromAccountId.value),
);

const grossCents = computed(() => brlInputToCents(amountStr.value));

const fromAccount = computed(() =>
  bankAccounts.value.find(b => b.id === fromAccountId.value) || null,
);

const insufficientBalance = computed(() => {
  if (!fromAccount.value) return false;
  if (fromAccount.value.current_balance_cents == null) return false;
  return grossCents.value > fromAccount.value.current_balance_cents;
});

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!fromAccountId.value || !toAccountId.value) return false;
  if (fromAccountId.value === toAccountId.value) return false;
  if (grossCents.value <= 0) return false;
  if (insufficientBalance.value) return false;
  return true;
});

// ── Aux data load ───────────────────────────────────────────────
async function loadAux() {
  try {
    const { data } = await FinancialV2.bankAccounts.index({ active: 'true' });
    bankAccounts.value = data?.data || [];
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[TransferModalV2] loadAux error', err);
  }
}

function reset() {
  occurredAt.value = new Date().toISOString().slice(0, 10);
  fromAccountId.value = null;
  toAccountId.value = null;
  amountStr.value = '';
  notes.value = '';
  submitting.value = false;
}

watch(
  () => props.show,
  (val) => {
    if (val) {
      reset();
      loadAux();
    }
  },
);

// Se trocar a conta de origem pra mesma da destino, limpa destino.
watch(fromAccountId, (val) => {
  if (val && val === toAccountId.value) toAccountId.value = null;
});

onMounted(() => {
  if (props.show) {
    reset();
    loadAux();
  }
});

function onAmountInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  amountStr.value = formatted;
  e.target.value = formatted;
}

// ── Submit ──────────────────────────────────────────────────────
async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const { data } = await FinancialV2.bankAccounts.transfer(fromAccountId.value, {
      to_bank_account_id: toAccountId.value,
      amount_cents: grossCents.value,
      occurred_at: occurredAt.value,
      notes: notes.value.trim() || null,
    });
    notifySuccess('Transferência registrada — saldos atualizados.');
    emit('confirm', data);
    emit('close');
  } catch (err) {
    const errors = err?.response?.data?.errors;
    const msg = Array.isArray(errors) ? errors.join('; ') : errors || err?.response?.data?.message;
    notifyError(msg || 'Erro ao registrar transferência');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="tf-v2__backdrop">
      <div class="tf-v2__modal" role="dialog" aria-modal="true">
        <!-- Header -->
        <header class="tf-v2__header">
          <div class="tf-v2__header-text">
            <h2 class="tf-v2__title">
              <i class="i-lucide-arrow-left-right tf-v2__title-icon" />
              Transferência Interna
            </h2>
            <p class="tf-v2__subtitle">
              Move dinheiro entre contas da clínica. <strong>Não afeta o DRE</strong>
              — é movimento neutro (saldos mudam, receita/despesa não).
            </p>
          </div>
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :disabled="submitting"
            @click="close"
          />
        </header>

        <!-- Body -->
        <div class="tf-v2__body">
          <div class="tf-v2__grid">
            <label class="tf-v2__field">
              <span class="tf-v2__field-label">Data *</span>
              <DatePickerBR v-model="occurredAt" />
            </label>

            <label class="tf-v2__field">
              <span class="tf-v2__field-label">Valor *</span>
              <div class="tf-v2__currency-wrap">
                <span class="tf-v2__currency-prefix">R$</span>
                <input
                  :value="amountStr"
                  type="text"
                  inputmode="numeric"
                  placeholder="0,00"
                  class="finv2-input tf-v2__currency-input"
                  @input="onAmountInput"
                />
              </div>
            </label>

            <label class="tf-v2__field">
              <span class="tf-v2__field-label">Conta Origem *</span>
              <FormSelect
                v-model="fromAccountId"
                :options="bankAccountOptions"
                placeholder="De onde sai o dinheiro"
                searchable
                auto-searchable
              />
            </label>

            <label class="tf-v2__field">
              <span class="tf-v2__field-label">Conta Destino *</span>
              <FormSelect
                v-model="toAccountId"
                :options="toAccountOptions"
                placeholder="Para onde vai"
                searchable
                auto-searchable
                :disabled="!fromAccountId"
              />
            </label>

            <label class="tf-v2__field tf-v2__field--full">
              <span class="tf-v2__field-label">
                Descrição
                <span class="tf-v2__field-hint">(opcional)</span>
              </span>
              <input
                v-model="notes"
                type="text"
                class="finv2-input"
                placeholder="Ex.: Sangria pra Bradesco, Suprimento do caixa"
              />
            </label>
          </div>

          <!-- Aviso saldo insuficiente -->
          <div v-if="insufficientBalance" class="tf-v2__warning">
            <i class="i-lucide-alert-triangle w-4 h-4" />
            <span>
              Saldo insuficiente na conta origem.
              Disponível: <strong>{{ centsToBRL(fromAccount.current_balance_cents) }}</strong>
            </span>
          </div>

          <!-- Resumo -->
          <section v-if="grossCents > 0 && fromAccountId && toAccountId" class="tf-v2__summary">
            <div class="tf-v2__summary-row">
              <span>Sai de</span>
              <strong>{{ bankAccounts.find(b => b.id === fromAccountId)?.name }}</strong>
            </div>
            <div class="tf-v2__summary-row">
              <span>Entra em</span>
              <strong>{{ bankAccounts.find(b => b.id === toAccountId)?.name }}</strong>
            </div>
            <div class="tf-v2__summary-row tf-v2__summary-row--total">
              <span>Valor</span>
              <strong>{{ centsToBRL(grossCents) }}</strong>
            </div>
          </section>
        </div>

        <!-- Footer -->
        <footer class="tf-v2__footer">
          <BeclinicButton
            variant="ghost"
            color="slate"
            label="Cancelar"
            :disabled="submitting"
            @click="close"
          />
          <BeclinicButton
            variant="solid"
            color="blue"
            icon="i-lucide-arrow-left-right"
            label="Transferir"
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
.tf-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999; padding: 0;
}
@media (min-width: 640px) {
  .tf-v2__backdrop { align-items: center; padding: 16px; }
}

.tf-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  border: 0; border-radius: 0;
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .tf-v2__modal {
    width: min(640px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.tf-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.tf-v2__title {
  margin: 0; font-size: 17px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.tf-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--slate-9)); }
.tf-v2__subtitle { margin: 4px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }

.tf-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 16px;
}

.tf-v2__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 640px) { .tf-v2__grid { grid-template-columns: 1fr; } }
.tf-v2__field { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.tf-v2__field--full { grid-column: 1 / -1; }
.tf-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: inline-flex; align-items: center; gap: 6px;
}
.tf-v2__field-hint { font-weight: 400; font-size: 11px; color: rgb(var(--slate-9)); }

.tf-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.tf-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.tf-v2__currency-input {
  padding-left: 32px; text-align: right;
  font-variant-numeric: tabular-nums;
}

.tf-v2__warning {
  display: flex; align-items: center; gap: 8px;
  padding: 10px 12px;
  border-radius: 8px;
  background: rgba(220, 38, 38, 0.10);
  border-left: 3px solid #dc2626;
  color: #991b1b; font-size: 13px;
  i { flex-shrink: 0; color: #dc2626; }
  strong { font-variant-numeric: tabular-nums; }
}
:root.dark .tf-v2__warning { color: #fca5a5; background: rgba(220, 38, 38, 0.18); }

.tf-v2__summary {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 12px 14px;
  display: flex; flex-direction: column; gap: 6px;
}
.tf-v2__summary-row {
  display: flex; justify-content: space-between; align-items: center;
  font-size: 13px;
  span { color: rgb(var(--slate-11)); font-weight: 500; }
  strong { color: rgb(var(--slate-12)); font-weight: 600; font-variant-numeric: tabular-nums; }
}
.tf-v2__summary-row--total {
  font-size: 15px;
  padding-top: 8px;
  border-top: 1px dashed rgb(var(--slate-5));
  strong { font-size: 17px; font-weight: 700; }
}

.tf-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
@media (max-width: 640px) {
  .tf-v2__footer { flex-direction: column-reverse; }
  .tf-v2__footer > * { width: 100%; }
}
</style>
