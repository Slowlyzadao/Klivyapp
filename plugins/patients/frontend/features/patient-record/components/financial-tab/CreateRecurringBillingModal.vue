<script setup>
/**
 * CreateRecurringBillingModal — criar mensalidade fixa de paciente.
 * Decisão 2026-05-28: contrato recorrente (Financial::RecurringBilling)
 * que gera Budget+Installment a cada período via job diário.
 *
 * Form:
 *   - Descrição (ex.: "Mensalidade ortodontia")
 *   - Valor R$ (por período)
 *   - Frequência (monthly default; bimonthly/quarterly/semiannual/annual)
 *   - Início (default hoje)
 *   - Fim (opcional — em branco = indeterminado, gera até cancelar)
 *   - Forma de pagamento (lista real de Settings)
 *   - Observações
 */
import { computed, ref, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import {
  parseCurrencyInput,
  onSubtotalInput,
} from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import FinancialV2 from '@plugins/financial/frontend/features/financial/v2/api/financialV2';

const props = defineProps({
  open: { type: Boolean, default: false },
  patientId: { type: [Number, String], required: true },
});

const emit = defineEmits(['close', 'created']);

const todayIso = () => new Date().toISOString().slice(0, 10);

const blankForm = () => ({
  description: '',
  frequency: 'monthly',
  start_date: todayIso(),
  end_date: null,
  payment_method_id: null,
  notes: '',
});

const form = ref(blankForm());
const amountRaw = ref('');
const submitting = ref(false);

const paymentMethods = ref([]);
const paymentMethodsLoading = ref(false);

const FREQUENCY_OPTIONS = [
  { value: 'monthly',    label: 'Mensal (a cada 1 mês)' },
  { value: 'bimonthly',  label: 'Bimestral (a cada 2 meses)' },
  { value: 'quarterly',  label: 'Trimestral (a cada 3 meses)' },
  { value: 'semiannual', label: 'Semestral (a cada 6 meses)' },
  { value: 'annual',     label: 'Anual (a cada 12 meses)' },
];

const paymentMethodOptions = computed(() => {
  const list = [...paymentMethods.value];
  list.sort((a, b) => {
    const pa = (a.provider || '').trim();
    const pb = (b.provider || '').trim();
    if (!pa && pb) return -1;
    if (pa && !pb) return 1;
    if (pa !== pb) return pa.localeCompare(pb, 'pt-BR');
    return (a.name || '').localeCompare(b.name || '', 'pt-BR');
  });
  return list.map(m => ({
    value: m.id,
    label: m.name,
    hint: (m.provider_alias || m.provider || '').trim() || null,
    raw: m,
  }));
});

async function loadPaymentMethods() {
  paymentMethodsLoading.value = true;
  try {
    const { data } = await FinancialV2.paymentMethods.index({ status: 'active' });
    paymentMethods.value = (data?.data || []).filter(m => m.status === 'active');
    if (!form.value.payment_method_id && paymentMethods.value[0]) {
      form.value.payment_method_id = paymentMethods.value[0].id;
    }
  } catch {
    paymentMethods.value = [];
  } finally {
    paymentMethodsLoading.value = false;
  }
}

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      form.value = blankForm();
      amountRaw.value = '';
      loadPaymentMethods();
    }
  },
);

const handleAmountInput = e => onSubtotalInput(e, amountRaw);

const canSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.description?.trim()) return false;
  if (parseCurrencyInput(amountRaw.value) <= 0) return false;
  if (!form.value.frequency) return false;
  if (!form.value.start_date) return false;
  if (!form.value.payment_method_id) return false;
  if (form.value.end_date && form.value.end_date < form.value.start_date) return false;
  return true;
});

const endBeforeStart = computed(
  () => form.value.end_date && form.value.start_date && form.value.end_date < form.value.start_date,
);

async function submit() {
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
    const amountCents = Math.round(parseCurrencyInput(amountRaw.value) * 100);
    await FinancialV2.recurringBillings.create({
      recurring_billing: {
        patient_id: props.patientId,
        description: form.value.description.trim(),
        amount_cents: amountCents,
        frequency: form.value.frequency,
        start_date: form.value.start_date,
        end_date: form.value.end_date || null,
        next_generation_at: form.value.start_date, // 1ª geração = data início
        payment_method_id: form.value.payment_method_id,
        notes: form.value.notes?.trim() || null,
      },
    });
    useNotification.success('Mensalidade criada. Vai gerar a 1ª cobrança em ' + form.value.start_date + '.');
    emit('created');
  } catch (e) {
    const msg = e?.response?.data?.errors?.join('; ') || e?.response?.data?.message || 'Erro ao criar mensalidade.';
    useNotification.error(msg);
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-stretch justify-center bg-black/70 backdrop-blur-sm sm:items-center sm:p-4"
  >
    <!-- Painel: white em light / slate-900 em dark. Bordas e textos seguem
         padrão Tailwind dark: variants ([[feedback-bug-visual-recorrente-estrutural]]). -->
    <div
      class="bg-white dark:bg-slate-900 border-0 border-slate-200 dark:border-slate-700 shadow-2xl w-full h-full flex flex-col overflow-hidden sm:max-w-lg sm:h-auto sm:max-h-[calc(100vh-32px)] sm:rounded-2xl sm:border"
    >
      <header class="flex-shrink-0 flex items-center justify-between p-6 border-b border-slate-200 dark:border-slate-700/50">
        <div>
          <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100 flex items-center gap-2">
            <i class="i-lucide-repeat text-violet-600 dark:text-violet-400" />
            Nova mensalidade fixa
          </h3>
          <p class="text-xs text-slate-600 dark:text-slate-400 mt-0.5">
            Cobra automaticamente a cada período até cancelar (ou até a data fim, se houver).
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </header>

      <div class="flex-1 overflow-y-auto p-6 space-y-4">
        <!-- Descrição -->
        <div>
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
            Descrição*
          </label>
          <input
            v-model="form.description"
            type="text"
            maxlength="200"
            placeholder="Ex.: Mensalidade ortodontia, Pacote consultas, Assinatura clube"
            class="form-input w-full"
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <!-- Valor por período -->
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
              Valor por período (R$)*
            </label>
            <div class="relative">
              <span
                class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 dark:text-slate-400 text-sm font-medium z-10 pointer-events-none"
              >R$</span>
              <input
                :value="amountRaw"
                type="text"
                inputmode="numeric"
                placeholder="0,00"
                style="padding-left: 2.25rem !important"
                class="form-input w-full font-mono"
                @input="handleAmountInput"
              />
            </div>
          </div>

          <!-- Frequência -->
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
              Frequência*
            </label>
            <FormSelect v-model="form.frequency" :options="FREQUENCY_OPTIONS" />
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <!-- Data início -->
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
              Início*
              <span class="text-xs text-slate-500 dark:text-slate-500 ml-1">(1ª cobrança)</span>
            </label>
            <DatePickerBR v-model="form.start_date" placeholder="DD/MM/AAAA" />
          </div>

          <!-- Data fim (opcional) -->
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
              Fim
              <span class="text-xs text-slate-500 dark:text-slate-500 ml-1">(opcional)</span>
            </label>
            <DatePickerBR v-model="form.end_date" placeholder="Indeterminado" />
            <p v-if="endBeforeStart" class="text-xs text-red-400 mt-1">
              Data fim deve ser igual ou posterior à data de início.
            </p>
          </div>
        </div>

        <!-- Forma de pagamento -->
        <div>
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
            Forma de pagamento*
          </label>
          <div v-if="paymentMethodsLoading" class="text-xs text-slate-600 dark:text-slate-400 py-2">
            <i class="i-lucide-loader-2 w-3 h-3 animate-spin inline-block mr-1" />
            Carregando…
          </div>
          <FormSelect
            v-else
            v-model="form.payment_method_id"
            :options="paymentMethodOptions"
            placeholder="Selecione…"
            auto-searchable
          >
            <template #selected="{ option }">
              <PaymentMethodBadge
                v-if="option?.raw"
                :kind="option.raw.kind"
                :method="option.raw"
                size="md"
                hide-installments
              />
            </template>
            <template #option="{ option }">
              <PaymentMethodBadge
                :kind="option.raw.kind"
                :method="option.raw"
                size="md"
                hide-installments
              />
              <span v-if="option.hint" class="ml-auto text-xs text-slate-600 dark:text-slate-400">
                <i class="i-lucide-building-2 w-3 h-3 inline-block mr-1" />
                {{ option.hint }}
              </span>
            </template>
          </FormSelect>
        </div>

        <!-- Observações -->
        <div>
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">
            Observações
          </label>
          <textarea
            v-model="form.notes"
            rows="2"
            placeholder="Notas internas sobre a mensalidade…"
            class="form-input w-full resize-none"
          />
        </div>

        <!-- Caixa explicativa: violet light/dark com contraste AA em ambos -->
        <div class="bg-violet-500/10 border border-violet-500/30 rounded-xl p-3 text-xs text-violet-800 dark:text-violet-200 leading-relaxed">
          <i class="i-lucide-info w-3 h-3 inline-block mr-1 align-text-bottom" />
          O motor recorrente gera <strong>1 cobrança a cada {{ FREQUENCY_OPTIONS.find(f => f.value === form.frequency)?.label.toLowerCase() }}</strong>
          a partir da data de início. Cada cobrança aparece no timeline do paciente e pode ser recebida normalmente.
          Você pode <strong>pausar</strong> ou <strong>cancelar</strong> a qualquer momento sem afetar as cobranças já geradas.
        </div>
      </div>

      <footer class="flex-shrink-0 p-6 border-t border-slate-200 dark:border-slate-700/50 flex justify-end gap-3">
        <BeclinicButton
          variant="ghost"
          color="slate"
          label="Cancelar"
          :disabled="submitting"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-check"
          label="Criar mensalidade"
          :is-loading="submitting"
          :disabled="!canSubmit"
          @click="submit"
        />
      </footer>
    </div>
  </div>
</template>
