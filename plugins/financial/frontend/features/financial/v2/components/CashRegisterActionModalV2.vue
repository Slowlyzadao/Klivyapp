<script setup>
/**
 * Modal multi-purpose pras 5 ações de Caixa (substitui prompt() nativo).
 *
 * Modes:
 *   - 'open'        → input: opening_balance (R$)
 *   - 'close'       → input: counted_balance (R$); mostra esperado vs contado e diferença em tempo real
 *   - 'withdraw'    → input: amount (R$); destino = conta bancária pré-resolvida
 *   - 'supplement'  → input: amount (R$); origem = conta bancária pré-resolvida
 *   - 'reopen'      → input: reason (textarea, obrigatório)
 *
 * Props:
 *   - show: Boolean
 *   - mode: String
 *   - register: Object (sessão atual, opcional pro mode='open')
 *   - bankAccountName: String (pros modes withdraw/supplement)
 *
 * Eventos:
 *   - close
 *   - confirm: payload normalizado pro endpoint (cents/string)
 */
import { ref, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, required: true },
  register: { type: Object, default: null },
  bankAccountName: { type: String, default: '' },
});

const emit = defineEmits(['close', 'confirm']);

const amountInput = ref('');
const reasonInput = ref('');
const submitting = ref(false);

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    amountInput.value = '';
    reasonInput.value = '';
    submitting.value = false;
  },
  { immediate: true },
);

// Conversão "1.234,56" / "1234,56" / "1234.56" → cents (int)
function brlToCents(text) {
  if (!text) return 0;
  const digitsOnly = String(text).trim().replace(/\s+/g, '');
  if (!digitsOnly) return 0;
  // Aceita formato BR (vírgula decimal) ou US (ponto decimal)
  // Se tem vírgula, ela é o separador decimal
  let normalized;
  if (digitsOnly.includes(',')) {
    normalized = digitsOnly.replace(/\./g, '').replace(',', '.');
  } else {
    normalized = digitsOnly;
  }
  const f = parseFloat(normalized);
  if (!Number.isFinite(f) || f < 0) return NaN;
  return Math.round(f * 100);
}

function centsToBRL(cents) {
  if (cents == null) return 'R$ 0,00';
  const v = cents / 100;
  return 'R$ ' + v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// ── Mode-specific config ──────────────────────────────────────────────
const MODE_CONFIG = {
  open: {
    title: 'Abrir caixa',
    icon: 'i-lucide-unlock',
    color: 'teal',
    inputType: 'amount',
    inputLabel: 'Saldo inicial em dinheiro',
    inputPlaceholder: 'Ex.: 100,00',
    confirmLabel: 'Abrir',
    hint: 'Quanto há de dinheiro físico no caixa AGORA, antes de iniciar a sessão.',
  },
  close: {
    title: 'Fechar caixa',
    icon: 'i-lucide-lock',
    color: 'ruby',
    inputType: 'amount',
    inputLabel: 'Valor contado em dinheiro',
    inputPlaceholder: 'Conte o dinheiro físico…',
    confirmLabel: 'Fechar caixa',
    hint: 'Conte fisicamente o caixa antes. Diferença será registrada e auditada.',
  },
  withdraw: {
    title: 'Sangria',
    icon: 'i-lucide-arrow-up-from-line',
    color: 'amber',
    inputType: 'amount',
    inputLabel: 'Valor a depositar',
    inputPlaceholder: 'Ex.: 500,00',
    confirmLabel: 'Registrar sangria',
    hint: 'Retira dinheiro do caixa e deposita na conta bancária.',
  },
  supplement: {
    title: 'Suprimento',
    icon: 'i-lucide-arrow-down-to-line',
    color: 'teal',
    inputType: 'amount',
    inputLabel: 'Valor a retirar',
    inputPlaceholder: 'Ex.: 200,00',
    confirmLabel: 'Registrar suprimento',
    hint: 'Retira da conta bancária e entrega no caixa (troco etc).',
  },
  reopen: {
    title: 'Reabrir caixa',
    icon: 'i-lucide-rotate-ccw',
    color: 'amber',
    inputType: 'reason',
    inputLabel: 'Motivo da reabertura',
    inputPlaceholder: 'Ex.: Esqueci de lançar uma sangria…',
    confirmLabel: 'Reabrir',
    hint: 'Ação auditada. Motivo obrigatório.',
  },
};

const config = computed(() => MODE_CONFIG[props.mode] || MODE_CONFIG.open);

// ── Computeds derived ────────────────────────────────────────────────
const expectedCents = computed(() => props.register?.calculated_expected_cents || 0);

const countedCents = computed(() => {
  if (props.mode !== 'close') return null;
  return brlToCents(amountInput.value);
});

const differenceCents = computed(() => {
  if (countedCents.value == null || !Number.isFinite(countedCents.value)) return null;
  return countedCents.value - expectedCents.value;
});

const differenceLabel = computed(() => {
  if (differenceCents.value == null) return null;
  if (differenceCents.value === 0) return 'Exato (zero diferença)';
  if (differenceCents.value > 0) return `+${centsToBRL(differenceCents.value)} (sobra)`;
  return `${centsToBRL(differenceCents.value)} (falta)`;
});

const differenceClass = computed(() => {
  if (differenceCents.value == null) return '';
  if (differenceCents.value === 0) return 'craction-v2__diff--neutral';
  if (differenceCents.value > 0) return 'craction-v2__diff--positive';
  return 'craction-v2__diff--negative';
});

// ── Validação ────────────────────────────────────────────────────────
const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (config.value.inputType === 'amount') {
    const cents = brlToCents(amountInput.value);
    return Number.isFinite(cents) && cents >= 0 && amountInput.value.trim() !== '';
  }
  if (config.value.inputType === 'reason') {
    return reasonInput.value.trim().length >= 3;
  }
  return false;
});

function buildPayload() {
  if (props.mode === 'open') {
    return { opening_balance_cents: brlToCents(amountInput.value) };
  }
  if (props.mode === 'close') {
    return { counted_balance_cents: brlToCents(amountInput.value) };
  }
  if (props.mode === 'withdraw' || props.mode === 'supplement') {
    return { amount_cents: brlToCents(amountInput.value) };
  }
  if (props.mode === 'reopen') {
    return { reason: reasonInput.value.trim() };
  }
  return {};
}

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    emit('confirm', buildPayload());
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
    <div v-if="show" class="craction-v2__backdrop">
      <div class="craction-v2__modal" role="dialog" aria-modal="true">
        <header class="craction-v2__header">
          <div>
            <h2 class="craction-v2__title">
              <i :class="config.icon" class="craction-v2__title-icon" />
              {{ config.title }}
            </h2>
            <p v-if="bankAccountName" class="craction-v2__subtitle">
              {{ mode === 'withdraw' ? 'Destino' : (mode === 'supplement' ? 'Origem' : 'Caixa') }}:
              <strong>{{ bankAccountName }}</strong>
            </p>
          </div>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="craction-v2__body">
          <!-- Mode close: mostra esperado e diferença viva -->
          <div v-if="mode === 'close'" class="craction-v2__expected-card">
            <span>Esperado pela sessão:</span>
            <strong>{{ centsToBRL(expectedCents) }}</strong>
          </div>

          <!-- Input principal -->
          <label class="craction-v2__field">
            <span class="craction-v2__field-label">
              {{ config.inputLabel }} <span class="craction-v2__required">*</span>
            </span>

            <input
              v-if="config.inputType === 'amount'"
              v-model="amountInput"
              type="text"
              inputmode="decimal"
              class="finv2-input craction-v2__amount-input"
              :placeholder="config.inputPlaceholder"
              autofocus
              @keyup.enter="submit"
            />

            <textarea
              v-else
              v-model="reasonInput"
              class="finv2-input"
              rows="3"
              :placeholder="config.inputPlaceholder"
              autofocus
            />

            <span class="craction-v2__field-hint">{{ config.hint }}</span>
          </label>

          <!-- Diferença em tempo real (só mode close) -->
          <div v-if="mode === 'close' && differenceCents != null" class="craction-v2__diff" :class="differenceClass">
            <i v-if="differenceCents === 0" class="i-lucide-check-circle" />
            <i v-else-if="differenceCents > 0" class="i-lucide-trending-up" />
            <i v-else class="i-lucide-trending-down" />
            <span>{{ differenceLabel }}</span>
          </div>
        </div>

        <footer class="craction-v2__footer">
          <BeclinicButton variant="ghost" color="slate" label="Cancelar" :disabled="submitting" @click="close" />
          <BeclinicButton
            variant="solid"
            :color="config.color"
            :icon="config.icon"
            :label="config.confirmLabel"
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
.craction-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .craction-v2__backdrop { align-items: center; padding: 16px; }
}

.craction-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .craction-v2__modal {
    width: min(460px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.craction-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.craction-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.craction-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--emerald-9)); }
.craction-v2__subtitle { margin: 6px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }

.craction-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.craction-v2__field { display: flex; flex-direction: column; gap: 6px; }
.craction-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.craction-v2__required { color: rgb(var(--ruby-9)); }
.craction-v2__field-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-style: italic;
}

.craction-v2__amount-input {
  font-size: 16px;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
}

.craction-v2__expected-card {
  padding: 10px 14px;
  background: rgba(59, 130, 246, 0.06);
  border-left: 3px solid rgb(var(--blue-8));
  border-radius: 8px;
  font-size: 13px;
  color: rgb(var(--slate-11));
  display: flex; justify-content: space-between; align-items: center;
  strong { color: rgb(var(--slate-12)); font-variant-numeric: tabular-nums; }
}

.craction-v2__diff {
  display: flex; align-items: center; gap: 8px;
  padding: 10px 12px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 600;
  i { width: 16px; height: 16px; }

  &--neutral  { background: rgba(100, 116, 139, 0.08); color: rgb(var(--slate-11)); }
  &--positive { background: rgba(16, 185, 129, 0.08);  color: rgb(var(--emerald-11)); }
  &--negative { background: rgba(244, 63, 94, 0.08);   color: rgb(var(--ruby-11)); }
}

.craction-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
