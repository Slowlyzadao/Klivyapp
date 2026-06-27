<script setup>
/**
 * Modal de criar NOVA taxa para uma forma de pagamento.
 *
 * Canon `mapa-financeiro.json` step 3: NUNCA editar taxa existente.
 * Inativar antiga e criar nova com nova `valid_from`. Por isso o modal só
 * tem modo CREATE — não há edição.
 *
 * Campos:
 *   - installments_count (1..max do método)
 *   - fee_percent (% → basis points)
 *   - fee_fixed_reais (R$ fixo → cents)
 *   - liquidation_days (D+N)
 *   - valid_from (data inicial)
 *   - valid_to (opcional, abre por default)
 *
 * Props:
 *   - show: Boolean
 *   - paymentMethod: Object (com .id e .max_installments)
 *
 * Eventos: close, confirm
 */
import { ref, computed, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../../api/financialV2';

const props = defineProps({
  show: { type: Boolean, default: false },
  paymentMethod: { type: Object, required: true },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const form = ref({
  installments_count: 1,
  fee_percent: '',
  fee_fixed_reais: '',
  liquidation_days: 0,
  valid_from: new Date().toISOString().slice(0, 10),
  valid_to: '',
});
const submitting = ref(false);

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;
    form.value = {
      installments_count: 1,
      fee_percent: '',
      fee_fixed_reais: '',
      liquidation_days: 0,
      valid_from: new Date().toISOString().slice(0, 10),
      valid_to: '',
    };
  },
  { immediate: true },
);

const maxInstallments = computed(() => props.paymentMethod?.max_installments || 1);

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.installments_count || form.value.installments_count < 1 || form.value.installments_count > maxInstallments.value) return false;
  if (!form.value.valid_from) return false;
  const pct = parseFloat(form.value.fee_percent);
  if (form.value.fee_percent !== '' && (!Number.isFinite(pct) || pct < 0 || pct > 100)) return false;
  const fixed = parseFloat(form.value.fee_fixed_reais);
  if (form.value.fee_fixed_reais !== '' && (!Number.isFinite(fixed) || fixed < 0)) return false;
  if (form.value.valid_to && form.value.valid_to < form.value.valid_from) return false;
  return true;
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const pct = parseFloat(form.value.fee_percent || '0');
    const fixed = parseFloat(form.value.fee_fixed_reais || '0');
    const payload = {
      payment_method_fee: {
        installments_count: parseInt(form.value.installments_count, 10),
        fee_percent_basis_points: Math.round(pct * 100), // 2.5% → 250
        fee_fixed_cents: Math.round(fixed * 100),
        liquidation_days: parseInt(form.value.liquidation_days || 0, 10),
        valid_from: form.value.valid_from,
        valid_to: form.value.valid_to || null,
        status: 'active',
      },
    };
    await FinancialV2.paymentMethodFees.create(props.paymentMethod.id, payload);
    notifySuccess('Taxa criada. Vigência ativa a partir de ' + form.value.valid_from);
    emit('confirm');
  } catch (err) {
    const msg = err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao criar taxa';
    notifyError(msg);
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

// Preview pra ajudar o operador a entender o impacto
const previewLine = computed(() => {
  const pct = parseFloat(form.value.fee_percent || '0');
  const fixed = parseFloat(form.value.fee_fixed_reais || '0');
  const installments = parseInt(form.value.installments_count, 10) || 1;
  const liq = parseInt(form.value.liquidation_days || 0, 10);

  const parts = [];
  if (pct > 0) parts.push(`${pct.toFixed(2)}%`);
  if (fixed > 0) parts.push(`R$ ${fixed.toFixed(2)} fixo`);
  if (parts.length === 0) parts.push('sem taxa');

  let liqText;
  if (liq === 0) liqText = 'D+0 (imediato)';
  else liqText = `D+${liq}`;

  return `Em ${installments}x: ${parts.join(' + ')} · liquidação ${liqText}`;
});
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="pmf-v2__backdrop">
      <div class="pmf-v2__modal" role="dialog" aria-modal="true">
        <header class="pmf-v2__header">
          <div>
            <h2 class="pmf-v2__title">
              <i class="i-lucide-percent pmf-v2__title-icon" />
              Nova taxa — {{ paymentMethod?.name }}
            </h2>
            <p class="pmf-v2__subtitle">
              Taxas são <strong>versionadas</strong>: para alterar uma vigente, inative a
              antiga e crie outra com nova data de início.
            </p>
          </div>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="pmf-v2__body">
          <div class="pmf-v2__row">
            <label class="pmf-v2__field">
              <span class="pmf-v2__field-label">
                Parcelas <span class="pmf-v2__required">*</span>
              </span>
              <input
                v-model.number="form.installments_count"
                type="number"
                :min="1"
                :max="maxInstallments"
                class="finv2-input"
              />
              <span class="pmf-v2__field-hint-mini">
                1 a {{ maxInstallments }} (limite do método)
              </span>
            </label>

            <label class="pmf-v2__field">
              <span class="pmf-v2__field-label">Liquidação (dias)</span>
              <input
                v-model.number="form.liquidation_days"
                type="number"
                min="0"
                max="180"
                class="finv2-input"
              />
              <span class="pmf-v2__field-hint-mini">D+N do recebimento na conta</span>
            </label>
          </div>

          <div class="pmf-v2__row">
            <label class="pmf-v2__field">
              <span class="pmf-v2__field-label">Taxa % (sobre o valor)</span>
              <input
                v-model="form.fee_percent"
                type="number"
                step="0.01"
                min="0"
                max="100"
                class="finv2-input"
                placeholder="Ex.: 2.50"
              />
            </label>

            <label class="pmf-v2__field">
              <span class="pmf-v2__field-label">Taxa fixa (R$)</span>
              <input
                v-model="form.fee_fixed_reais"
                type="number"
                step="0.01"
                min="0"
                class="finv2-input"
                placeholder="Ex.: 0.30"
              />
            </label>
          </div>

          <div class="pmf-v2__row">
            <label class="pmf-v2__field">
              <span class="pmf-v2__field-label">
                Vigência inicial <span class="pmf-v2__required">*</span>
              </span>
              <DatePickerBR
                v-model="form.valid_from"
                placeholder="DD/MM/AAAA"
                :clearable="false"
              />
            </label>
            <label class="pmf-v2__field">
              <span class="pmf-v2__field-label">Vigência final (opcional)</span>
              <DatePickerBR
                v-model="form.valid_to"
                placeholder="Em branco = aberta"
                :min="form.valid_from || null"
              />
              <span class="pmf-v2__field-hint-mini">Em branco = aberta (até inativar)</span>
            </label>
          </div>

          <div class="pmf-v2__preview">
            <i class="i-lucide-eye" />
            <strong>Preview:</strong>
            <span>{{ previewLine }}</span>
          </div>

          <div class="pmf-v2__warning">
            <i class="i-lucide-alert-triangle" />
            <span>
              Se já existe taxa ativa para essa combinação de parcelas e período, o backend
              vai rejeitar (constraint de não-sobreposição). Inative a anterior primeiro.
            </span>
          </div>
        </div>

        <footer class="pmf-v2__footer">
          <BeclinicButton variant="ghost" color="slate" label="Cancelar" :disabled="submitting" @click="close" />
          <BeclinicButton
            variant="solid"
            color="blue"
            icon="i-lucide-check"
            label="Criar taxa"
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
.pmf-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .pmf-v2__backdrop { align-items: center; padding: 16px; }
}

.pmf-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .pmf-v2__modal {
    width: min(580px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.pmf-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.pmf-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.pmf-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--emerald-9)); }
.pmf-v2__subtitle {
  margin: 6px 0 0;
  font-size: 12px;
  color: rgb(var(--slate-9));
  line-height: 1.5;
  max-width: 460px;
}

.pmf-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.pmf-v2__row {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }
}

.pmf-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.pmf-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.pmf-v2__required { color: rgb(var(--ruby-9)); }
.pmf-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

.pmf-v2__preview {
  display: flex; align-items: center; gap: 8px;
  padding: 10px 12px;
  background: rgba(16, 185, 129, 0.06);
  border-left: 3px solid rgb(var(--emerald-9));
  border-radius: 8px;
  font-size: 12px;
  color: rgb(var(--slate-11));
  i { width: 14px; height: 14px; color: rgb(var(--emerald-10)); }
  strong { color: rgb(var(--slate-12)); }
}

.pmf-v2__warning {
  display: flex; gap: 8px;
  padding: 10px 12px;
  background: rgba(245, 158, 11, 0.06);
  border-left: 3px solid rgb(var(--amber-8));
  border-radius: 8px;
  font-size: 11px;
  color: rgb(var(--slate-11));
  line-height: 1.5;
  i { width: 14px; height: 14px; color: rgb(var(--amber-10)); flex-shrink: 0; margin-top: 2px; }
}

.pmf-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
