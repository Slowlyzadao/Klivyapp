<script setup>
/**
 * EditInstallmentModal — edita uma parcela pendente (canon BUG-02).
 *
 * Permite alterar valor, vencimento e forma de pagamento de uma parcela
 * que ainda NÃO foi paga. Bloqueia edição de parcelas com received_amount > 0
 * (canon: "para editar precisa estornar primeiro").
 *
 * Mostra contexto do orçamento (descrição + origem PT) e preview do novo
 * total do orçamento ao mudar valor — backend recalcula total = soma das
 * parcelas (EditApprovedBudget.update_installments).
 *
 * Parent recebe o evento `confirm` com:
 *   { budgetId, installmentId, payload: { amount_cents, due_date, payment_method } }
 * e chama `FinancialV2.budgets.updateInstallments(budgetId, installments_array)`
 * via composable `useFinancialActions.editInstallment`.
 */
import { ref, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import { formatCurrency, parseCurrencyInput } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import { PAYMENT_METHOD_OPTIONS } from '@plugins/patients/frontend/constants/financial';

const props = defineProps({
  open: { type: Boolean, default: false },
  installment: { type: Object, default: null },
  budgetId: { type: [Number, String, null], default: null },
  /* Entry pai (lançamento da timeline) — fornece contexto:
     description, origin.label (Plano de Tratamento), total do orçamento,
     lista de parcelas siblings (pra somar e mostrar preview do novo total). */
  entry: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'confirm']);

const form = ref({ amount_raw: '', due_date: '', payment_method: 'pix' });

watch(
  () => [props.open, props.installment],
  ([open, inst]) => {
    if (!open || !inst) return;
    const cents = inst.amount_cents != null ? inst.amount_cents : Math.round(Number(inst.amount || 0) * 100);
    form.value = {
      amount_raw: (cents / 100).toFixed(2).replace('.', ','),
      due_date: inst.due_date,
      payment_method: inst.payment_method || 'pix',
    };
  },
  { immediate: true }
);

const isReceived = computed(() => {
  const inst = props.installment;
  if (!inst) return false;
  return inst.status === 'pago' || inst.status === 'reembolsado' || (inst.received_amount_cents || 0) > 0;
});

const newAmountCents = computed(() => {
  const n = parseCurrencyInput(form.value.amount_raw);
  return Math.round((Number.isFinite(n) ? n : 0) * 100);
});

const currentAmountCents = computed(() => {
  const inst = props.installment;
  if (!inst) return 0;
  return inst.amount_cents != null ? inst.amount_cents : Math.round(Number(inst.amount || 0) * 100);
});

// Total ATUAL do orçamento (soma das parcelas vivas) — usa entry.total se vier
// pronto do builder, senão soma a lista de installments do entry.
const currentBudgetTotalCents = computed(() => {
  const e = props.entry;
  if (!e) return 0;
  if (typeof e.total === 'number') return Math.round(e.total * 100);
  const list = e.installments || [];
  return list
    .filter(i => i.status !== 'cancelado')
    .reduce((sum, i) => {
      const c = i.amount_cents != null ? i.amount_cents : Math.round(Number(i.amount || 0) * 100);
      return sum + c;
    }, 0);
});

// Total NOVO = total atual − valor antigo da parcela + valor novo.
const newBudgetTotalCents = computed(() =>
  currentBudgetTotalCents.value - currentAmountCents.value + newAmountCents.value
);

const totalDeltaCents = computed(
  () => newBudgetTotalCents.value - currentBudgetTotalCents.value
);

const totalChanged = computed(() => totalDeltaCents.value !== 0);

const formatBRL = cents => formatCurrency((cents || 0) / 100);

const deltaLabel = computed(() => {
  const d = totalDeltaCents.value;
  if (d === 0) return null;
  const sign = d > 0 ? '+' : '−';
  return `${sign}${formatBRL(Math.abs(d))}`;
});

const handleConfirm = () => {
  if (!props.installment || isReceived.value) return;
  const amount_cents = Math.round(parseCurrencyInput(form.value.amount_raw) * 100);
  if (amount_cents <= 0) return;
  emit('confirm', {
    budgetId: props.budgetId,
    installmentId: props.installment.id,
    payload: {
      amount_cents,
      due_date: form.value.due_date,
      payment_method: form.value.payment_method,
    },
  });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
  >
    <div
      class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-lg"
    >
      <div
        class="flex items-center justify-between p-6 border-b border-slate-700/50"
      >
        <div>
          <h3
            class="text-lg font-semibold text-slate-100 flex items-center gap-2"
          >
            <i class="i-lucide-pencil text-blue-400" />
            Editar parcela
          </h3>
          <p class="text-xs text-slate-400 mt-0.5">
            Apenas parcelas pendentes podem ser editadas.
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div v-if="installment" class="p-6 space-y-4">
        <p
          v-if="isReceived"
          class="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-lg px-3 py-2.5"
        >
          Esta parcela já foi recebida. Para editar, estorne o pagamento primeiro
          (canon BUG-02).
        </p>

        <template v-else>
          <!-- Contexto do orçamento -->
          <div
            v-if="entry"
            class="bg-slate-800/60 border border-slate-700/60 rounded-lg px-3 py-2.5 space-y-1"
          >
            <div class="flex items-center gap-2 text-sm text-slate-200 font-medium">
              <i class="i-lucide-file-text w-3.5 h-3.5 flex-shrink-0 text-slate-400" />
              <span>{{ entry.description || 'Orçamento' }}</span>
            </div>
            <div
              v-if="entry.origin?.label"
              class="flex items-center gap-2 text-xs text-slate-400"
            >
              <i class="i-lucide-link w-3 h-3 flex-shrink-0" />
              <span>{{ entry.origin.label }}</span>
            </div>
          </div>

          <p class="text-sm text-slate-400">
            Parcela
            <strong class="text-slate-200">{{ installment.number }}/{{ installment.total }}</strong>
            · valor atual:
            <strong class="text-slate-200">{{ formatBRL(currentAmountCents) }}</strong>
          </p>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              Novo valor (R$) *
            </label>
            <div class="relative">
              <span
                class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm font-medium z-10 pointer-events-none"
              >R$</span>
              <input
                v-model="form.amount_raw"
                type="text"
                inputmode="decimal"
                placeholder="0,00"
                style="padding-left: 2.25rem !important"
                class="form-input w-full font-mono"
              />
            </div>
          </div>

          <!-- Preview do impacto no total do orçamento -->
          <div
            v-if="totalChanged && currentBudgetTotalCents > 0"
            class="rounded-lg px-3 py-2.5 text-xs flex gap-2.5 border-l-4"
            :class="totalDeltaCents > 0
              ? 'bg-amber-500/10 border-amber-500 text-amber-100'
              : 'bg-emerald-500/10 border-emerald-500 text-emerald-100'"
          >
            <i class="i-lucide-info w-4 h-4 flex-shrink-0 mt-0.5" />
            <div class="flex-1 space-y-1">
              <div class="flex flex-wrap items-center gap-1.5">
                <span class="text-slate-300">Total do orçamento:</span>
                <span class="line-through text-slate-500">
                  {{ formatBRL(currentBudgetTotalCents) }}
                </span>
                <i class="i-lucide-arrow-right w-3 h-3 text-slate-400" />
                <strong>{{ formatBRL(newBudgetTotalCents) }}</strong>
                <span
                  class="font-mono"
                  :class="totalDeltaCents > 0 ? 'text-amber-300' : 'text-emerald-300'"
                >
                  ({{ deltaLabel }})
                </span>
              </div>
              <div class="text-slate-500">
                Outras parcelas pendentes não são alteradas.
              </div>
            </div>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              Vencimento *
            </label>
            <DatePickerBR v-model="form.due_date" />
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              Forma de pagamento
            </label>
            <FormSelect
              v-model="form.payment_method"
              :options="PAYMENT_METHOD_OPTIONS"
              clearable
            />
          </div>
        </template>
      </div>

      <div class="p-6 border-t border-slate-700/50 flex justify-end gap-3">
        <BeclinicButton
          variant="ghost"
          color="slate"
          label="Cancelar"
          @click="emit('close')"
        />
        <BeclinicButton
          v-if="!isReceived"
          variant="solid"
          color="blue"
          icon="i-lucide-check"
          label="Salvar alterações"
          :is-loading="loading"
          :disabled="loading"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
