<script setup>
/**
 * PaymentSplitBuilder — lista de parcelas (modo Customizado do PaymentPlanWizardV2).
 *
 * Cada parcela é um CARD (não mais linha de tabela) — visual premium 2026-05-28:
 *   - Index badge 36×36 (variante azul quando crédito Nx)
 *   - Field block: label CAPS pequeno em cima, input padronizado 40px embaixo
 *   - Valor base com prefixo "R$", DatePicker BR, FormSelect + PaymentMethodBadge,
 *     Parc. (só p/ crédito), Cliente paga (valor + meta com tag "+ Taxa"/"Sem taxa"),
 *     botão remover (ghost → ruby no hover)
 *
 * Pernas de crédito Nx (N > 1) ganham:
 *   - is-card (borda + bg azul-claro)
 *   - Drawer "Cobrança recorrente no cartão" DENTRO do card (não mais sub-row),
 *     com conector L-shape ligando o idx badge ao ícone do drawer
 *
 * Não chama API — recebe `pernaAggregates` (já agregado pelo wizard, que faz
 * a expansão crédito Nx → N cobranças antes de simular).
 */
import { computed, ref, watch } from 'vue';
import { brlInputToCents, centsToBRL, centsToInputString, formatCurrencyInput, splitCents } from '../../composables/useMoney';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';

const props = defineProps({
  // Array de { amount_str: string, amount_cents: number, due_date: 'YYYY-MM-DD',
  //   payment_method_id: number|null, card_installments: number|null }
  // `card_installments` = parcelamento DESSA perna na maquininha (só p/ crédito).
  modelValue: { type: Array, required: true },
  paymentMethods: { type: Array, default: () => [] },
  // Simulação AGREGADA por perna — vem do wizard, que expande pernas multi-cartão
  // (crédito Nx → N cobranças) antes de simular e soma os resultados de volta no
  // nível da perna. Index = idx da perna no modelValue. Shape por item:
  //   { amount_cents, fee_amount_cents, net_amount_cents, passes_fee_to_patient, fee_resolved }
  pernaAggregates: { type: Array, default: () => [] },
  // Total alvo (centavos) — se soma das parcelas != total, mostra warning
  targetTotalCents: { type: Number, default: 0 },
});

const emit = defineEmits(['update:modelValue']);

const paymentMethodOptions = computed(() =>
  [...props.paymentMethods]
    .sort((a, b) => {
      const pa = (a.provider || '').trim();
      const pb = (b.provider || '').trim();
      if (!pa && pb) return -1;
      if (pa && !pb) return 1;
      if (pa !== pb) return pa.localeCompare(pb, 'pt-BR');
      return (a.name || '').localeCompare(b.name || '', 'pt-BR');
    })
    .map(m => ({
      value: m.id,
      label: m.name,
      hint: (m.provider_alias || m.provider || '').trim() || null,
      raw: m,
    }))
);

const findPaymentMethod = id => props.paymentMethods.find(m => m.id === id) || null;

const sumCents = computed(() => props.modelValue.reduce((acc, r) => acc + (r.amount_cents || 0), 0));
const difference = computed(() => sumCents.value - props.targetTotalCents);

function onAmountInput(idx, event) {
  const formatted = formatCurrencyInput(event.target.value);
  const cents = brlInputToCents(formatted);
  const next = props.modelValue.map((r, i) =>
    i === idx ? { ...r, amount_str: formatted, amount_cents: cents } : r
  );
  emit('update:modelValue', next);
}

function onFieldChange(idx, field, value) {
  const next = props.modelValue.map((r, i) =>
    i === idx ? { ...r, [field]: value } : r
  );
  emit('update:modelValue', next);
}

// Crédito parcela na maquininha → mostra o campo "Parc." e mantém o
// card_installments. Trocar p/ forma não-crédito zera o campo (o MDR daquela
// forma não depende de parcelamento). Default 1x ao virar crédito.
function isCreditMethod(method) {
  return !!method && method.kind === 'credito' && method.supports_installments;
}
function methodForRow(idx) {
  return findPaymentMethod(props.modelValue[idx]?.payment_method_id);
}
function isCreditRow(idx) {
  return isCreditMethod(methodForRow(idx));
}
function maxInstForRow(idx) {
  return methodForRow(idx)?.max_installments || 24;
}

// Card visual destacado (drawer + idx badge azul) só quando crédito + N > 1.
function isCreditWithInstallments(idx) {
  return isCreditRow(idx) && Number(props.modelValue[idx]?.card_installments) > 1;
}

function onMethodChange(idx, value) {
  const method = findPaymentMethod(value);
  const credit = isCreditMethod(method);
  const next = props.modelValue.map((r, i) =>
    i === idx
      ? { ...r, payment_method_id: value, card_installments: credit ? (r.card_installments || 1) : null }
      : r
  );
  emit('update:modelValue', next);
}

function onCardInstallmentsInput(idx, event) {
  const n = Number.parseInt(event.target.value, 10);
  const val = Number.isFinite(n) && n >= 1 ? n : null;
  onFieldChange(idx, 'card_installments', val);
}

function addRow() {
  const last = props.modelValue[props.modelValue.length - 1];
  const lastDue = last?.due_date;
  const lastMethod = findPaymentMethod(last?.payment_method_id);
  const credit = isCreditMethod(lastMethod);

  // Pré-preenche com o saldo restante (total - já configurado) — operador
  // raramente quer abrir nova perna com 0; quando há saldo, pula o passo de
  // digitar de novo. Cai pra '' quando já fechou tudo (operador edita).
  const remaining = props.targetTotalCents - sumCents.value;
  const initialCents = remaining > 0 ? remaining : 0;
  const initialStr = initialCents > 0 ? centsToInputString(initialCents) : '';

  const next = [...props.modelValue, {
    amount_str: initialStr,
    amount_cents: initialCents,
    due_date: lastDue || new Date().toISOString().slice(0, 10),
    payment_method_id: last?.payment_method_id || null,
    card_installments: credit ? (last?.card_installments || 1) : null,
  }];
  emit('update:modelValue', next);
}

function removeRow(idx) {
  if (props.modelValue.length <= 1) return;
  emit('update:modelValue', props.modelValue.filter((_, i) => i !== idx));
}

function feeForRow(idx) {
  // pernaAggregates já vem indexado por perna (1 entry por linha);
  // sem necessidade de buscar por row_index.
  return props.pernaAggregates?.[idx] || null;
}

// Collapse/expand do drawer de timeline por card. Estado local (Set de índices)
// — reseta quando add/remove perna porque o índice de uma perna recolhida pode
// passar a apontar pra outra. UX: default expandido.
const collapsedIdx = ref(new Set());

function isCollapsed(idx) {
  return collapsedIdx.value.has(idx);
}

function toggleCollapsed(idx) {
  const next = new Set(collapsedIdx.value);
  if (next.has(idx)) next.delete(idx);
  else next.add(idx);
  collapsedIdx.value = next;
}

watch(() => props.modelValue.length, () => {
  // Tamanho da lista mudou — limpa pra evitar índice apontando p/ outra perna.
  collapsedIdx.value = new Set();
});

// Cliente paga total da perna: agregado da simulação (com taxa repassada) ou
// fallback no base (sem simulação ainda).
function clientPaysFor(idx) {
  const agg = feeForRow(idx);
  return agg?.amount_cents ?? props.modelValue[idx]?.amount_cents ?? 0;
}

// Per-installment "amount base" quando a perna é crédito Nx — usado no drawer.
function perInstallmentBase(row) {
  const n = Number(row?.card_installments) || 1;
  return n > 1 ? Math.round((row.amount_cents || 0) / n) : (row.amount_cents || 0);
}

// Taxa (MDR) POR cobrança no cartão — distribui o fee total da perna pelas N
// parcelas. Para crédito Nx isso é fiel ao que ocorre (MDR aplicado por parcela
// com o mesmo bps). Cai pra 0 se a simulação ainda não chegou ou se a perna
// não tem fee resolvido.
function perInstallmentFee(idx, n) {
  const agg = feeForRow(idx);
  if (!agg) return 0;
  const total = agg.fee_amount_cents || 0;
  return Math.round(total / Math.max(1, Number(n) || 1));
}

// Cobranças que serão geradas para uma perna de crédito Nx — espelha a
// expansão do wizard (`expandCardInstallments`): mesmo `splitCents` (resto
// na última) + cadência mensal de 30 dias. Mantido para outros consumidores.
function installmentsForDisplay(row) {
  const n = Number(row?.card_installments) || 1;
  if (n < 2) return [];
  const pieces = splitCents(row.amount_cents || 0, n);
  return pieces.map((amount_cents, k) => ({
    amount_cents,
    due_date: addDaysLocal(row.due_date, k * 30),
  }));
}

function addDaysLocal(isoDate, days) {
  if (!isoDate) return isoDate;
  const d = new Date(isoDate);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

// Parse-safe (sem TZ surprise) — mesmo idiom do wizard.
function formatDateBR(iso) {
  if (!iso) return '—';
  const parts = String(iso).slice(0, 10).split('-');
  if (parts.length !== 3) return iso;
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}
</script>

<template>
  <div class="split-builder">

    <div class="installments">
      <template v-for="(row, idx) in modelValue" :key="idx">
        <div class="installment" :class="{ 'is-card': isCreditWithInstallments(idx) }">
          <div class="installment-main">
            <div class="idx">{{ idx + 1 }}</div>

            <div class="field field-val">
              <span class="field-label">Valor base</span>
              <div class="input-wrapper">
                <span class="input-prefix">R$</span>
                <input
                  :value="row.amount_str"
                  type="text"
                  inputmode="decimal"
                  placeholder="0,00"
                  class="input input--with-prefix"
                  @input="onAmountInput(idx, $event)"
                />
              </div>
            </div>

            <div class="field field-due">
              <span class="field-label">
                {{ isCreditWithInstallments(idx) ? 'Primeiro vencimento' : 'Vencimento' }}
              </span>
              <DatePickerBR
                :model-value="row.due_date"
                placeholder="DD/MM/AAAA"
                @update:modelValue="v => onFieldChange(idx, 'due_date', v)"
              />
            </div>

            <div class="field field-pay">
              <span class="field-label">Forma de pagamento</span>
              <FormSelect
                :model-value="row.payment_method_id"
                :options="paymentMethodOptions"
                placeholder="Selecione…"
                auto-searchable
                @update:modelValue="v => onMethodChange(idx, v)"
              >
                <template #selected="{ option }">
                  <PaymentMethodBadge
                    v-if="option?.raw"
                    :kind="option.raw.kind"
                    :method="option.raw"
                    size="sm"
                    hide-installments
                  />
                </template>
                <template #option="{ option }">
                  <PaymentMethodBadge
                    :kind="option.raw.kind"
                    :method="option.raw"
                    size="sm"
                    hide-installments
                  />
                  <span v-if="option.hint" class="pm-hint">
                    <i class="i-lucide-building-2 w-3 h-3" /> {{ option.hint }}
                  </span>
                </template>
              </FormSelect>
            </div>

            <div class="field field-parc">
              <span class="field-label">Parc.</span>
              <input
                v-if="isCreditRow(idx)"
                :value="row.card_installments || ''"
                type="number"
                min="1"
                :max="maxInstForRow(idx)"
                class="input input--parc"
                placeholder="1x"
                title="Em quantas vezes essa perna foi parcelada no cartão"
                @input="onCardInstallmentsInput(idx, $event)"
              />
              <div v-else class="parc-na" title="Não se aplica a esta forma">—</div>
            </div>

            <div class="field field-cli">
              <span class="field-label">Cliente paga</span>
              <div class="money">
                <span class="money-value">{{ centsToBRL(clientPaysFor(idx)) }}</span>
                <span v-if="feeForRow(idx)" class="money-meta">
                  <template v-if="feeForRow(idx).fee_amount_cents > 0">
                    <span class="tag tag--warn">+ Taxa</span>
                    {{ centsToBRL(feeForRow(idx).fee_amount_cents) }}
                  </template>
                  <template v-else>Sem taxa</template>
                </span>
                <span v-else class="money-meta money-meta--pending">…</span>
              </div>
            </div>

            <div class="installment-actions">
              <button
                v-if="isCreditWithInstallments(idx)"
                type="button"
                class="action-btn collapse-btn"
                :title="isCollapsed(idx) ? 'Expandir parcelas geradas' : 'Recolher parcelas geradas'"
                :aria-expanded="!isCollapsed(idx)"
                @click="toggleCollapsed(idx)"
              >
                <i
                  :class="isCollapsed(idx)
                    ? 'i-lucide-chevron-down w-4 h-4'
                    : 'i-lucide-chevron-up w-4 h-4'"
                />
              </button>
              <button
                type="button"
                class="action-btn remove-btn"
                :disabled="modelValue.length <= 1"
                :title="modelValue.length <= 1 ? 'Mínimo 1 parcela' : 'Remover'"
                @click="removeRow(idx)"
              >
                <i class="i-lucide-trash-2 w-4 h-4" />
              </button>
            </div>
          </div>

          <!-- Drawer "cobrança recorrente no cartão" — só p/ crédito Nx (N > 1).
               Recolhível pelo chevron no canto direito do card.
               Header com summary + timeline vertical com cada cobrança listada
               (dot na linha, tag k/N, valor, data, status "Programada"). -->
          <div
            v-if="isCreditWithInstallments(idx) && !isCollapsed(idx)"
            class="recurring-info"
          >
            <div class="recurring-header">
              <div class="recurring-icon">
                <i class="i-lucide-refresh-cw w-4 h-4" />
              </div>
              <div class="recurring-text">
                Cobrança recorrente no cartão —
                <strong>{{ row.card_installments }} cobranças mensais de
                {{ centsToBRL(perInstallmentBase(row)) }} cada</strong>
              </div>
            </div>
            <div class="recurring-timeline">
              <div
                v-for="(inst, k) in installmentsForDisplay(row)"
                :key="k"
                class="timeline-item"
              >
                <span class="timeline-dot" />
                <span class="timeline-seq">{{ k + 1 }}/{{ row.card_installments }}</span>
                <span class="timeline-amount">{{ centsToBRL(inst.amount_cents) }}</span>
                <span class="timeline-date">
                  <i class="i-lucide-calendar w-3 h-3" />
                  {{ formatDateBR(inst.due_date) }}
                </span>
                <span
                  v-if="perInstallmentFee(idx, row.card_installments) > 0"
                  class="timeline-fee"
                  title="MDR repassada por parcela do cartão"
                >
                  <span class="tag tag--warn">+ Taxa</span>
                  {{ centsToBRL(perInstallmentFee(idx, row.card_installments)) }}
                </span>
                <span v-else class="timeline-fee timeline-fee--zero">Sem taxa</span>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>

    <button type="button" class="add-installment" @click="addRow">
      <i class="i-lucide-plus w-4 h-4" /> Adicionar parcela
    </button>

    <div
      v-if="targetTotalCents > 0"
      class="validation-row"
      :class="difference === 0 ? 'is-ok' : 'is-warn'"
    >
      <div class="check">
        <i v-if="difference === 0" class="i-lucide-check w-3 h-3" />
        <i v-else class="i-lucide-alert-triangle w-3 h-3" />
      </div>
      <template v-if="difference === 0">
        Parcelas somam <strong>{{ centsToBRL(sumCents) }}</strong> = total do orçamento.
      </template>
      <template v-else>
        Soma das parcelas <strong>{{ centsToBRL(sumCents) }}</strong>
        <span v-if="difference > 0">excede</span><span v-else>está abaixo do</span>
        total ({{ centsToBRL(targetTotalCents) }}) em
        <strong>{{ centsToBRL(Math.abs(difference)) }}</strong>.
      </template>
    </div>

  </div>
</template>

<style scoped lang="scss">
.split-builder {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

// ─── Lista de cards ──────────────────────────────────────────────────────
.installments {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.installment {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 16px;
  overflow: hidden;
  transition: border-color 200ms, box-shadow 200ms;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);

  &:hover {
    border-color: rgb(var(--slate-6));
    box-shadow: 0 1px 3px rgba(15, 23, 42, 0.06), 0 1px 2px rgba(15, 23, 42, 0.04);
  }
  &.is-card {
    border-color: rgb(var(--blue-6));
    background: linear-gradient(180deg, rgb(var(--blue-2) / 0.5) 0%, rgb(var(--slate-1)) 45%);
  }
}

.installment-main {
  display: grid;
  // Larguras padronizadas (2026-05-28):
  //   - idx = 36px (= largura exata do badge; antes 44px sobrava 8px e o gap
  //     entre idx e valor parecia maior que os outros 12px)
  //   - valor / cliente-paga = 1fr (apertados, numéricos)
  //   - vencimento = 150px fixo (DD/MM/AAAA + ícone calendar)
  //   - forma = 1.3fr (badge + dropdown precisa de respiro)
  //   - parc = 70px fixo
  //   - actions = 80px FIXO (não `auto`!) — row com chevron tem 2 botões e row
  //     sem chevron tem 1; com auto o tamanho mudava por row e desalinhava as
  //     1fr cols entre as pernas. Fixo garante mesma grid em todas as rows.
  grid-template-columns: 36px 1fr 150px 1.3fr 70px 1fr 80px;
  gap: 12px;
  align-items: end;
  padding: 14px 16px;
}

// ─── Index badge ─────────────────────────────────────────────────────────
.idx {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  border: 1px solid rgb(var(--slate-4));
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 14px;
  font-variant-numeric: tabular-nums;
  margin-bottom: 1px;  // alinha com base dos inputs

  .installment.is-card & {
    background: rgb(var(--blue-3));
    color: rgb(var(--blue-11));
    border-color: rgb(var(--blue-6));
  }
}

// ─── Field block (label CAPS em cima + input abaixo) ─────────────────────
.field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
  width: 100%; // explícito p/ grid items que herdam stretch — evita sobra branca
}
.field-label {
  font-size: 10.5px;
  font-weight: 600;
  color: rgb(var(--slate-9));
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

// ─── Inputs padronizados ─────────────────────────────────────────────────
.input {
  width: 100%;
  height: 40px;
  padding: 0 12px;
  border: 1px solid rgb(var(--slate-6));
  border-radius: 8px;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-12));
  font-size: 14px;
  font-weight: 600;
  font-family: inherit;
  transition: border-color 160ms, box-shadow 160ms;

  &:hover { border-color: rgb(var(--slate-7)); }
  &:focus {
    outline: none;
    border-color: rgb(var(--blue-8));
    box-shadow: 0 0 0 3px rgb(var(--blue-5) / 0.4);
  }
  &::placeholder { color: rgb(var(--slate-8)); font-weight: 500; }

  // !important obrigatório: existe regra GLOBAL do core Chatwoot em
  // app/javascript/dashboard/assets/scss/_base.scss aplicando `field-base h-10`
  // (= padding `px-3` = 12px) em todo `input[type]:not(.reset-base):not(.no-margin):not(...)`.
  // A cadeia de 11 `:not()` sobe a especificidade pra (0,11,1), batendo o meu
  // `.input.input--with-prefix[data-v-X]` (0,3,1) no cascade. `.finv2-input`
  // sofre o mesmo conflito e resolve do mesmo jeito (`_layout.scss` linhas
  // 334-351). 48px = 12 (left) + ~24 (largura real de "R$" Inter 600 14px) + 12 (gap).
  &.input--with-prefix { padding-left: 48px !important; }
  &.input--parc {
    text-align: center;
    font-variant-numeric: tabular-nums;
    padding-left: 12px !important;
    padding-right: 4px !important;
  }
}
.input-wrapper { position: relative; width: 100%; }
.input-prefix {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: rgb(var(--slate-9));
  font-size: 13px;
  font-weight: 600;
  pointer-events: none;
}

// Parc. desabilitado (forma sem parcelamento) — visual neutro tipo "—"
.parc-na {
  height: 40px;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-8));
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 14px;
}

// ─── Cliente paga ────────────────────────────────────────────────────────
.money {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
  padding-top: 2px;
}
.money-value {
  font-size: 16px;
  font-weight: 700;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
  line-height: 1.2;

  .installment.is-card & { color: rgb(var(--blue-11)); }
}
.money-meta {
  font-size: 11px;
  color: rgb(var(--slate-9));
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-variant-numeric: tabular-nums;
}
.money-meta--pending { color: rgb(var(--slate-8)); }
.tag {
  padding: 1px 7px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}
.tag--warn {
  background: rgb(var(--amber-3));
  color: rgb(var(--amber-11));
  border: 1px solid rgb(var(--amber-5));
}

// ─── Ações do card (chevron recolher + remover) ──────────────────────────
.installment-actions {
  display: inline-flex;
  align-items: center;
  justify-content: flex-end; // remover sempre no canto direito (alinhado entre
                             // rows com/sem chevron) — col actions é fixa 80px
  gap: 4px;
  margin-bottom: 1px; // alinha base com inputs
  width: 100%;        // grid item: ocupa toda a col fixa
}
.action-btn {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  border: 1px solid transparent;
  background: transparent;
  color: rgb(var(--slate-9));
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  transition: background 160ms, color 160ms, border-color 160ms;

  &:disabled { opacity: 0.3; cursor: not-allowed; }
}
// Chevron recolher/expandir — hover neutral (não destrutivo)
.collapse-btn:hover:not(:disabled) {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
  border-color: rgb(var(--slate-5));
}
// Remover — hover ruby (ação destrutiva)
.remove-btn:hover:not(:disabled) {
  background: rgb(var(--ruby-2));
  color: rgb(var(--ruby-10));
  border-color: rgb(var(--ruby-5));
}

// ─── Drawer "cobrança recorrente" dentro do card ─────────────────────────
// Layout: header (refresh icon + summary) + timeline vertical com cada cobrança
// numa linha (dot + tag k/N + valor + data + status "Programada").
.recurring-info {
  border-top: 1px dashed rgb(var(--blue-6));
  background: linear-gradient(180deg, rgb(var(--blue-2) / 0.4) 0%, rgb(var(--blue-2) / 0.65) 100%);
  padding: 14px 18px 16px;
}
.recurring-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}
.recurring-icon {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  // Solid bg + fallback Tailwind (blue-600) — `--blue-10` nem sempre resolve.
  background: rgb(var(--blue-9, 37 99 235));
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 3px 8px -2px rgb(var(--blue-9, 37 99 235) / 0.4);
  flex-shrink: 0;
}
.recurring-text {
  color: rgb(var(--slate-11));
  font-size: 13px;
  line-height: 1.5;

  strong {
    color: rgb(var(--blue-11, 30 64 175));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
}

// ─── Timeline vertical com as N cobranças ────────────────────────────────
.recurring-timeline {
  position: relative;
  padding-left: 24px;

  // Linha vertical conectando os dots — começa no meio do 1º item e termina
  // no meio do último, então top/bottom = ~metade da altura de um item (~16px).
  &::before {
    content: '';
    position: absolute;
    left: 7px;
    top: 16px;
    bottom: 16px;
    width: 1.5px;
    background: rgb(var(--blue-6));
    border-radius: 2px;
  }
}
.timeline-item {
  position: relative;
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 7px 0;

  &:not(:last-child) {
    border-bottom: 1px solid rgb(var(--blue-5) / 0.45);
  }
}
.timeline-dot {
  position: absolute;
  left: -22px;
  top: 50%;
  transform: translateY(-50%);
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: rgb(var(--slate-1));
  border: 2px solid rgb(var(--blue-8, 59 130 246));
  flex-shrink: 0;
  z-index: 1;
}
.timeline-seq {
  padding: 2px 9px;
  background: rgb(var(--blue-3));
  border: 1px solid rgb(var(--blue-5));
  border-radius: 6px;
  font-size: 11px;
  font-weight: 700;
  color: rgb(var(--blue-11, 30 64 175));
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}
.timeline-amount {
  font-size: 14px;
  font-weight: 700;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}
.timeline-date {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-left: auto;  // empurra date+status pra direita
  font-size: 13px;
  color: rgb(var(--slate-11));
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;

  i { color: rgb(var(--slate-9)); }
}
// Taxa por cobrança — reusa a tag amber do "+ Taxa" da célula Cliente paga
.timeline-fee {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-11));
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}
.timeline-fee--zero {
  font-weight: 500;
  font-style: italic;
  color: rgb(var(--slate-9));
}

// (regra mobile do .timeline-item agora vive no bloco @media (max-width: 640px)
//  consolidado lá embaixo junto com o resto do layout responsivo)

// ─── Add new ─────────────────────────────────────────────────────────────
.add-installment {
  width: 100%;
  height: 52px;
  border-radius: 12px;
  border: 1.5px dashed rgb(var(--slate-6));
  background: transparent;
  color: rgb(var(--slate-10));
  font-size: 14px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  transition: all 160ms;

  &:hover {
    background: rgb(var(--blue-2));
    border-color: rgb(var(--blue-8));
    border-style: solid;
    color: rgb(var(--blue-11));
  }
}

// ─── Validation pill ─────────────────────────────────────────────────────
.validation-row {
  padding: 12px 16px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 13px;
  font-weight: 500;
  line-height: 1.4;

  .check {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    color: #fff;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }
  strong {
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  // `--green-*` NÃO existe no design system Klivy (só slate/blue/ruby/teal/amber)
  // — fallbacks Tailwind garantem render. Ver memory project_emerald_token_inexistente.
  &.is-ok {
    background: rgb(var(--green-2, 220 252 231));
    border: 1px solid rgb(var(--green-5, 134 239 172));
    color: rgb(var(--green-11, 21 128 61));
    .check { background: rgb(var(--green-9, 34 197 94)); }
  }
  &.is-warn {
    background: rgb(var(--amber-2));
    border: 1px solid rgb(var(--amber-6));
    color: rgb(var(--amber-11));
    .check { background: rgb(var(--amber-9)); }
  }
}

// FormSelect option hint
.pm-hint {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-left: 6px;
  font-size: 11px;
  color: rgb(var(--slate-10));
}

// ─── Responsive ──────────────────────────────────────────────────────────
// 640-960px: layout 2-col compacto, actions empilha vertical no canto.
@media (max-width: 960px) {
  .installment-main {
    // Actions = `auto` (não fixo 80px) — col vira só o necessário pros 2 botões
    // empilhados (36px), eliminando a sobra branca que aparecia no desktop em
    // viewport estreita. parc/cli em row própria, parc com input limitado a 80px.
    grid-template-columns: 44px 1fr 1fr auto;
    grid-template-areas:
      "idx  val   val   actions"
      "idx  due   pay   actions"
      "idx  parc  cli   actions";
    gap: 10px;
    padding: 12px 14px;
    align-items: stretch;
  }
  .idx { grid-area: idx; align-self: start; margin-top: 22px; }
  .field-val   { grid-area: val; }
  .field-due   { grid-area: due; }
  .field-pay   { grid-area: pay; }
  .field-parc  { grid-area: parc; }
  .field-cli   { grid-area: cli; }
  // parc não precisa de 1fr — limita o input a 80px e empurra pra esquerda
  // pra cli ganhar o resto da row visualmente sem ficar com sobra na parc.
  .field-parc .input--parc,
  .field-parc .parc-na { max-width: 80px; }

  .installment-actions {
    grid-area: actions;
    flex-direction: column;
    align-self: start;
    margin-top: 22px;
    margin-bottom: 0;
  }
}

// <640px: layout 1-col vertical pra phones pequenos — tudo empilhado, actions
// continua na coluna lateral pra não ocupar uma linha inteira só pra ela.
@media (max-width: 640px) {
  .installment {
    border-radius: 12px;
  }
  .installment-main {
    grid-template-columns: 36px 1fr auto;
    grid-template-areas:
      "idx  val   actions"
      "idx  due   actions"
      "idx  pay   actions"
      "idx  parc  actions"
      "idx  cli   actions";
    gap: 8px;
    padding: 12px;
  }
  .idx { margin-top: 22px; width: 32px; height: 32px; font-size: 13px; }
  .field-parc .input--parc,
  .field-parc .parc-na { max-width: 100%; } // single col → fill
  .installment-actions { margin-top: 18px; }

  .recurring-info { padding: 12px 14px 14px; }
  .timeline-item {
    flex-wrap: wrap;
    .timeline-date { margin-left: 0; }
  }
}
</style>
