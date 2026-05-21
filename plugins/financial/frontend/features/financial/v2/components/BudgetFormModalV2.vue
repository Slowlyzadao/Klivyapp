<script setup>
/**
 * Modal de criação de Orçamento (canon F-12, F-14, F-16).
 *
 * Fluxo:
 *   1. Buscar paciente (autocomplete via PatientsAPI)
 *   2. Adicionar 1+ itens (descrição + qty + preço unitário)
 *   3. Definir parcelas: uniforme (N parcelas iguais com distribuição canônica
 *      do resto na última — §6 valores em centavos) OU personalizado (lista
 *      de parcelas com valor/data próprios — modo "parcelas com condições
 *      diferentes" §3)
 *   4. POST /financial/v2/budgets cria como draft
 *   5. Se "aprovar e gerar" marcado, chama POST /budgets/:id/approve em
 *      seguida → gera as parcelas em A Receber
 *
 * Não cria item-clinico ou treatment_plan — esse fluxo é avulso (orcamento).
 * Para PT clínico use Prontuário → Plano de Tratamento → aprovar.
 */
import { ref, computed, onMounted, watch } from 'vue';
import FinancialV2 from '../api/financialV2';
import PatientsAPI from '@plugins/patients/frontend/api/patients';
import { brlInputToCents, centsToBRL, splitCents } from '../composables/useMoney';
import FinSearchInput from './FinSearchInput.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const props = defineProps({
  show: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'created']);

const PAYMENT_METHODS = [
  { value: 'dinheiro', label: 'Dinheiro' },
  { value: 'pix', label: 'PIX' },
  { value: 'debito', label: 'Débito' },
  { value: 'credito', label: 'Crédito' },
  { value: 'boleto', label: 'Boleto' },
  { value: 'multiplas', label: 'Múltiplas (entrada + parcelas distintas)' },
];

// ----- patient picker -----
const patientQuery = ref('');
const patientResults = ref([]);
const selectedPatient = ref(null);
const patientLoading = ref(false);

let patientSearchTimer = null;
watch(patientQuery, (value) => {
  if (selectedPatient.value && selectedPatient.value.name === value) return;
  clearTimeout(patientSearchTimer);
  if (!value || value.length < 2) {
    patientResults.value = [];
    return;
  }
  patientSearchTimer = setTimeout(searchPatients, 250);
});

async function searchPatients() {
  patientLoading.value = true;
  try {
    const { data } = await PatientsAPI.get({ search: patientQuery.value, perPage: 10 });
    patientResults.value = data?.payload || data?.data || data?.patients || [];
  } catch {
    patientResults.value = [];
  } finally {
    patientLoading.value = false;
  }
}

function selectPatient(p) {
  selectedPatient.value = p;
  patientQuery.value = p.name;
  patientResults.value = [];
}

function clearPatient() {
  selectedPatient.value = null;
  patientQuery.value = '';
}

// ----- items -----
const items = ref([emptyItem()]);
function emptyItem() {
  return { description: '', quantity: 1, unit_price_str: '' };
}
function addItem() { items.value.push(emptyItem()); }
function removeItem(idx) {
  if (items.value.length === 1) return;
  items.value.splice(idx, 1);
}

const subtotalCents = computed(() => {
  return items.value.reduce((sum, it) => {
    const unit = brlInputToCents(it.unit_price_str || '0');
    const qty = Number(it.quantity) || 0;
    return sum + unit * qty;
  }, 0);
});

// ----- discount -----
const discount = ref({ kind: 'none', value_str: '' });
const discountCents = computed(() => {
  if (discount.value.kind === 'fixo') {
    return brlInputToCents(discount.value.value_str || '0');
  }
  if (discount.value.kind === 'percentual') {
    const bp = Math.round(parseFloat(discount.value.value_str || '0') * 100); // 5,5 → 550 bp
    return Math.round((subtotalCents.value * bp) / 10000);
  }
  return 0;
});

const totalCents = computed(() => Math.max(0, subtotalCents.value - discountCents.value));

// ----- installments plan -----
const installmentsMode = ref('uniform'); // uniform | custom
const installmentsCount = ref(1);
const firstDueDate = ref(todayIso());
const intervalDays = ref(30);
const paymentMethod = ref('pix');
const customInstallments = ref([]); // array of { amount_str, due_date, payment_method }

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

const uniformInstallments = computed(() => {
  if (installmentsMode.value !== 'uniform') return [];
  const total = totalCents.value;
  if (total <= 0 || installmentsCount.value <= 0) return [];
  const cents = splitCents(total, Number(installmentsCount.value));
  return cents.map((c, idx) => ({
    number: idx + 1,
    amount_cents: c,
    due_date: addDays(firstDueDate.value, idx * Number(intervalDays.value)),
    payment_method: paymentMethod.value,
  }));
});

function addDays(isoDate, days) {
  const d = new Date(`${isoDate}T00:00:00`);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

watch(installmentsMode, (mode) => {
  if (mode === 'custom' && customInstallments.value.length === 0) {
    // Inicia com plano uniforme convertido pra editável
    customInstallments.value = uniformInstallments.value.map((i) => ({
      amount_str: (i.amount_cents / 100).toFixed(2).replace('.', ','),
      due_date: i.due_date,
      payment_method: i.payment_method,
    }));
  }
});

function addCustomInstallment() {
  const last = customInstallments.value[customInstallments.value.length - 1] || {
    amount_str: '0,00',
    due_date: firstDueDate.value,
    payment_method: paymentMethod.value,
  };
  customInstallments.value.push({
    amount_str: '0,00',
    due_date: addDays(last.due_date, Number(intervalDays.value)),
    payment_method: last.payment_method,
  });
}

function removeCustomInstallment(idx) {
  if (customInstallments.value.length === 1) return;
  customInstallments.value.splice(idx, 1);
}

const customTotalCents = computed(() =>
  customInstallments.value.reduce((s, i) => s + brlInputToCents(i.amount_str || '0'), 0),
);

// ----- submit -----
const approveAfter = ref(true);
const notes = ref('');
const validUntil = ref('');

const submitting = ref(false);
const errorMessage = ref('');

const canSubmit = computed(() => {
  if (!selectedPatient.value) return false;
  if (!items.value.some((i) => i.description.trim() && brlInputToCents(i.unit_price_str) > 0)) return false;
  if (totalCents.value <= 0) return false;
  if (installmentsMode.value === 'custom') {
    if (customInstallments.value.length === 0) return false;
    return customTotalCents.value === totalCents.value;
  }
  return Number(installmentsCount.value) > 0;
});

async function submit() {
  if (!canSubmit.value || submitting.value) return;
  submitting.value = true;
  errorMessage.value = '';
  try {
    // 1. Cria o budget como draft
    const budgetPayload = {
      budget: {
        patient_id: selectedPatient.value.id,
        origin: 'orcamento',
        status: 'rascunho',
        installments_count: installmentsMode.value === 'uniform'
          ? Number(installmentsCount.value)
          : customInstallments.value.length,
        payment_method: paymentMethod.value,
        notes: notes.value || null,
        valid_until: validUntil.value || null,
        discount_cents: discountCents.value,
        discount_kind: discount.value.kind === 'none' ? null : discount.value.kind,
        items: items.value
          .filter((it) => it.description.trim() && brlInputToCents(it.unit_price_str) > 0)
          .map((it) => ({
            description: it.description,
            quantity: Number(it.quantity) || 1,
            unit_price_cents: brlInputToCents(it.unit_price_str),
            total_cents: brlInputToCents(it.unit_price_str) * (Number(it.quantity) || 1),
          })),
      },
    };
    const { data: budget } = await FinancialV2.budgets.create(budgetPayload);

    // 2. Se aprovar marcado, chama o approve com o plano de parcelas
    if (approveAfter.value) {
      const approvePayload = {
        payment_method: paymentMethod.value,
        first_due_date: firstDueDate.value,
        interval_days: Number(intervalDays.value),
      };
      if (installmentsMode.value === 'custom') {
        approvePayload.installments_plan = customInstallments.value.map((i) => ({
          amount_cents: brlInputToCents(i.amount_str),
          due_date: i.due_date,
          payment_method: i.payment_method,
        }));
      }
      await FinancialV2.budgets.approve(budget.id, approvePayload);
    }

    emit('created', budget);
    resetForm();
    emit('close');
  } catch (err) {
    errorMessage.value = err?.response?.data?.errors?.join('; ') || err?.message || 'Erro ao criar orçamento';
  } finally {
    submitting.value = false;
  }
}

function resetForm() {
  clearPatient();
  items.value = [emptyItem()];
  discount.value = { kind: 'none', value_str: '' };
  installmentsMode.value = 'uniform';
  installmentsCount.value = 1;
  firstDueDate.value = todayIso();
  intervalDays.value = 30;
  paymentMethod.value = 'pix';
  customInstallments.value = [];
  approveAfter.value = true;
  notes.value = '';
  validUntil.value = '';
  errorMessage.value = '';
}

function close() {
  emit('close');
}
</script>

<template>
  <div v-if="show" class="modal-overlay" role="dialog" aria-modal="true">
    <div class="modal">
      <header class="modal-header">
        <h2>Novo orçamento</h2>
        <button type="button" class="btn-close" aria-label="Fechar" @click="close">×</button>
      </header>

      <div class="modal-body">
        <p v-if="errorMessage" class="error" role="alert">{{ errorMessage }}</p>

        <!-- Paciente -->
        <fieldset class="block">
          <legend>Paciente</legend>
          <div v-if="!selectedPatient" class="patient-picker">
            <FinSearchInput v-model="patientQuery" placeholder="Buscar paciente por nome…" />
            <div v-if="patientLoading" class="loading-inline">Buscando…</div>
            <ul v-if="patientResults.length" class="patient-results">
              <li v-for="p in patientResults" :key="p.id" @click="selectPatient(p)">
                <strong>{{ p.name }}</strong>
                <small v-if="p.email">{{ p.email }}</small>
              </li>
            </ul>
          </div>
          <div v-else class="patient-selected">
            <span><strong>{{ selectedPatient.name }}</strong>
              <small v-if="selectedPatient.email">{{ selectedPatient.email }}</small>
            </span>
            <button type="button" class="btn-link" @click="clearPatient">Trocar</button>
          </div>
        </fieldset>

        <!-- Itens -->
        <fieldset class="block">
          <legend>Itens do orçamento</legend>
          <div class="items">
            <div v-for="(it, idx) in items" :key="idx" class="item-row">
              <input v-model="it.description" type="text" placeholder="Descrição (ex: Restauração + Limpeza)" class="desc" />
              <input v-model.number="it.quantity" type="number" min="1" placeholder="Qtd" class="qty" />
              <input v-model="it.unit_price_str" type="text" inputmode="decimal" placeholder="Valor unitário" class="price" />
              <button type="button" class="btn-remove" :disabled="items.length === 1" @click="removeItem(idx)">×</button>
            </div>
            <button type="button" class="btn-add" @click="addItem">+ adicionar item</button>
          </div>
          <div class="totals">
            <span>Subtotal: <strong>{{ centsToBRL(subtotalCents) }}</strong></span>
          </div>
        </fieldset>

        <!-- Desconto -->
        <fieldset class="block">
          <legend>Desconto (opcional)</legend>
          <div class="discount-row">
            <select v-model="discount.kind">
              <option value="none">Sem desconto</option>
              <option value="percentual">Percentual (%)</option>
              <option value="fixo">Fixo (R$)</option>
            </select>
            <input
              v-if="discount.kind !== 'none'"
              v-model="discount.value_str"
              type="text"
              inputmode="decimal"
              :placeholder="discount.kind === 'percentual' ? '5,00 (%)' : '50,00 (R$)'"
            />
            <span v-if="discount.kind !== 'none'" class="discount-preview">
              − {{ centsToBRL(discountCents) }}
            </span>
          </div>
          <p class="total-final">
            <strong>Total: {{ centsToBRL(totalCents) }}</strong>
          </p>
        </fieldset>

        <!-- Parcelas -->
        <fieldset class="block">
          <legend>Parcelas</legend>
          <div class="mode-toggle">
            <label><input v-model="installmentsMode" type="radio" value="uniform" /> Uniforme (N parcelas iguais)</label>
            <label><input v-model="installmentsMode" type="radio" value="custom" /> Personalizado (valores/datas distintos)</label>
          </div>

          <div v-if="installmentsMode === 'uniform'" class="uniform-plan">
            <div class="row">
              <label>
                <span>Quantidade</span>
                <input v-model.number="installmentsCount" type="number" min="1" max="60" />
              </label>
              <label>
                <span>Forma padrão</span>
                <select v-model="paymentMethod">
                  <option v-for="pm in PAYMENT_METHODS" :key="pm.value" :value="pm.value">{{ pm.label }}</option>
                </select>
              </label>
              <label>
                <span>1ª venc.</span>
                <input v-model="firstDueDate" type="date" />
              </label>
              <label>
                <span>Intervalo (dias)</span>
                <input v-model.number="intervalDays" type="number" min="1" max="365" />
              </label>
            </div>
            <table v-if="uniformInstallments.length" class="preview">
              <thead><tr><th>#</th><th>Vencimento</th><th>Forma</th><th>Valor</th></tr></thead>
              <tbody>
                <tr v-for="i in uniformInstallments" :key="i.number">
                  <td>{{ i.number }}</td>
                  <td>{{ i.due_date }}</td>
                  <td>{{ PAYMENT_METHODS.find((p) => p.value === i.payment_method)?.label }}</td>
                  <td>{{ centsToBRL(i.amount_cents) }}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div v-else class="custom-plan">
            <div class="row">
              <label>
                <span>1ª venc.</span>
                <input v-model="firstDueDate" type="date" />
              </label>
              <label>
                <span>Intervalo (dias)</span>
                <input v-model.number="intervalDays" type="number" min="1" max="365" />
              </label>
            </div>
            <div v-for="(ci, idx) in customInstallments" :key="idx" class="custom-row">
              <span class="num">#{{ idx + 1 }}</span>
              <input v-model="ci.amount_str" type="text" inputmode="decimal" placeholder="Valor" />
              <input v-model="ci.due_date" type="date" />
              <select v-model="ci.payment_method">
                <option v-for="pm in PAYMENT_METHODS" :key="pm.value" :value="pm.value">{{ pm.label }}</option>
              </select>
              <button type="button" class="btn-remove" :disabled="customInstallments.length === 1" @click="removeCustomInstallment(idx)">×</button>
            </div>
            <button type="button" class="btn-add" @click="addCustomInstallment">+ adicionar parcela</button>
            <p v-if="customTotalCents !== totalCents" class="hint warn">
              Soma das parcelas: {{ centsToBRL(customTotalCents) }} ≠ Total: {{ centsToBRL(totalCents) }}
            </p>
            <p v-else class="hint ok">
              ✓ Parcelas somam {{ centsToBRL(customTotalCents) }} = total do orçamento
            </p>
          </div>
        </fieldset>

        <!-- Detalhes finais -->
        <fieldset class="block">
          <legend>Detalhes</legend>
          <div class="row">
            <label class="full">
              <span>Observações</span>
              <textarea v-model="notes" rows="2" placeholder="Opcional"></textarea>
            </label>
            <label>
              <span>Validade do orçamento</span>
              <input v-model="validUntil" type="date" />
            </label>
          </div>
          <label class="check">
            <input v-model="approveAfter" type="checkbox" />
            <span>Aprovar e gerar parcelas em A Receber agora <small>(BUG-02 — só desmarque se quiser editar antes de aprovar)</small></span>
          </label>
        </fieldset>
      </div>

      <footer class="modal-footer">
        <button type="button" class="btn-skip" :disabled="submitting" @click="close">Cancelar</button>
        <button type="button" class="btn-confirm" :disabled="!canSubmit || submitting" @click="submit">
          {{ submitting ? 'Salvando…' : approveAfter ? 'Criar e aprovar' : 'Salvar como rascunho' }}
        </button>
      </footer>
    </div>
  </div>
</template>

<style scoped lang="scss">
.modal-overlay {
  position: fixed; inset: 0; background: rgba(15, 23, 42, 0.5);
  display: grid; place-items: center; z-index: 1000; padding: 24px; overflow: auto;
}
.modal {
  width: min(900px, 100%); max-height: 90vh; background: white; border-radius: 12px;
  display: flex; flex-direction: column; box-shadow: 0 20px 60px rgba(0,0,0,0.3);
}
.modal-header {
  display: flex; justify-content: space-between; align-items: center;
  padding: 16px 20px; border-bottom: 1px solid var(--s-200, #e2e8f0);
  h2 { margin: 0; font-size: 18px; }
  .btn-close {
    background: transparent; border: 0; font-size: 28px; line-height: 1; cursor: pointer; color: var(--s-500, #64748b);
    &:hover { color: var(--s-800, #1e293b); }
  }
}
.modal-body { padding: 20px; overflow-y: auto; flex: 1; }
.modal-footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 16px 20px; border-top: 1px solid var(--s-200, #e2e8f0);
}
.error { color: var(--r-700, #b91c1c); padding: 8px 12px; border-radius: 6px;
  background: var(--r-50, #fef2f2); border: 1px solid var(--r-200, #fecaca); font-size: 13px; margin-bottom: 12px; }
.block {
  border: 1px solid var(--s-200, #e2e8f0); border-radius: 8px; padding: 14px;
  margin-bottom: 12px;
  legend { font-size: 11px; font-weight: 700; padding: 0 6px; color: var(--s-700, #334155); text-transform: uppercase; letter-spacing: 0.04em; }
}
.patient-picker {
  position: relative;
  .loading-inline { font-size: 12px; color: var(--s-500, #64748b); padding: 6px 0; }
  .patient-results {
    position: absolute; top: 100%; left: 0; right: 0; background: white;
    border: 1px solid var(--s-200, #e2e8f0); border-radius: 6px; max-height: 200px;
    overflow-y: auto; z-index: 5; box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    list-style: none; padding: 4px; margin: 0;
    li { padding: 8px 10px; border-radius: 4px; cursor: pointer; display: flex; flex-direction: column; gap: 2px;
      &:hover { background: var(--s-50, #f8fafc); }
      strong { font-size: 13px; }
      small { font-size: 11px; color: var(--s-500, #64748b); }
    }
  }
}
.patient-selected {
  display: flex; justify-content: space-between; align-items: center;
  padding: 10px 12px; background: var(--g-50, #f0fdf4); border-radius: 6px;
  span { display: flex; flex-direction: column; gap: 2px; small { font-size: 12px; color: var(--s-600, #475569); } }
}
.btn-link { background: transparent; border: 0; color: var(--w-600, #1e88e5); cursor: pointer; font-size: 12px;
  &:hover { text-decoration: underline; }
}
.items {
  display: flex; flex-direction: column; gap: 6px;
  .item-row {
    display: grid; grid-template-columns: 2fr 0.4fr 0.8fr auto; gap: 8px; align-items: center;
    .desc, .qty, .price { padding: 6px 10px; border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; font-size: 13px; }
    .qty { text-align: center; }
    .price { text-align: right; }
  }
}
.btn-remove {
  width: 28px; height: 28px; border-radius: 50%; background: transparent;
  border: 1px solid var(--s-300, #cbd5e1); color: var(--s-600, #475569); cursor: pointer; font-size: 16px;
  &:hover:not(:disabled) { background: var(--r-50, #fef2f2); border-color: var(--r-300, #fca5a5); color: var(--r-700, #b91c1c); }
  &:disabled { opacity: 0.4; cursor: not-allowed; }
}
.btn-add {
  margin-top: 4px; padding: 4px 10px; background: transparent; border: 1px dashed var(--s-300, #cbd5e1);
  border-radius: 4px; cursor: pointer; font-size: 12px; color: var(--s-700, #334155);
  &:hover { background: var(--s-50, #f8fafc); }
}
.totals {
  margin-top: 8px; text-align: right; font-size: 13px; color: var(--s-700, #334155);
}
.discount-row {
  display: flex; gap: 8px; align-items: center;
  select, input { padding: 6px 10px; border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; font-size: 13px; }
  .discount-preview { color: var(--r-600, #dc2626); font-weight: 600; font-size: 13px; }
}
.total-final { margin: 8px 0 0; text-align: right; font-size: 16px; }
.mode-toggle {
  display: flex; gap: 16px; margin-bottom: 12px;
  label { display: flex; align-items: center; gap: 6px; font-size: 13px; cursor: pointer; }
}
.row {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 8px;
  label { display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: var(--s-600, #475569);
    &.full { grid-column: 1 / -1; }
    input, select, textarea { padding: 6px 10px; border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; font-size: 13px; font-family: inherit; }
  }
}
.preview {
  width: 100%; margin-top: 12px; border-collapse: collapse; font-size: 12px;
  th, td { padding: 4px 8px; text-align: left; border-bottom: 1px solid var(--s-100, #f1f5f9); }
  th { font-size: 10px; color: var(--s-600, #475569); text-transform: uppercase; }
  td:last-child, th:last-child { text-align: right; }
}
.custom-plan {
  .custom-row {
    display: grid; grid-template-columns: 36px 1fr 1fr 1.5fr auto; gap: 8px; align-items: center; margin-top: 6px;
    .num { font-size: 12px; color: var(--s-500, #64748b); }
    input, select { padding: 6px 10px; border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; font-size: 13px; }
  }
  .hint { font-size: 12px; margin-top: 8px;
    &.warn { color: var(--r-700, #b91c1c); }
    &.ok { color: var(--g-700, #15803d); }
  }
}
.check {
  display: flex; gap: 8px; align-items: flex-start; margin-top: 12px; cursor: pointer; font-size: 13px;
  small { display: block; color: var(--s-500, #64748b); font-size: 11px; margin-top: 2px; }
}
.btn-confirm {
  padding: 8px 18px; background: var(--w-600, #1e88e5); color: white;
  border: 0; border-radius: 6px; cursor: pointer; font-weight: 600; font-size: 13px;
  &:disabled { opacity: 0.5; cursor: not-allowed; }
}
.btn-skip {
  padding: 8px 16px; background: transparent; color: var(--s-700, #334155);
  border: 1px solid var(--s-300, #cbd5e1); border-radius: 6px; cursor: pointer; font-weight: 500; font-size: 13px;
  &:hover { background: var(--s-50, #f8fafc); }
}
</style>
