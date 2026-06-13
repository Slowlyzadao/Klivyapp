<script setup>
/**
 * Modal de motivo de estorno de despesa (substitui prompt() nativo em PayablesV2).
 *
 * Estorno é ação destrutiva auditada — motivo é obrigatório e fica no AuditLog.
 *
 * Props:
 *   - show: Boolean
 *   - expense: Object — { description, total_cents, paid_at }
 *
 * Eventos:
 *   - close
 *   - confirm: { reason }
 */
import { ref, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  expense: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const reason = ref('');
const submitting = ref(false);

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    reason.value = '';
    submitting.value = false;
  },
  { immediate: true },
);

function centsToBRL(cents) {
  if (cents == null) return '—';
  return 'R$ ' + (cents / 100).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDate(d) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('pt-BR');
}

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  return reason.value.trim().length >= 3;
});

function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    emit('confirm', { reason: reason.value.trim() });
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
    <div v-if="show" class="rev-v2__backdrop">
      <div class="rev-v2__modal" role="dialog" aria-modal="true">
        <header class="rev-v2__header">
          <div>
            <h2 class="rev-v2__title">
              <i class="i-lucide-undo-2 rev-v2__title-icon" />
              Estornar pagamento
            </h2>
            <p class="rev-v2__subtitle">Ação auditada. Motivo fica registrado no histórico.</p>
          </div>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="rev-v2__body">
          <div v-if="expense" class="rev-v2__summary">
            <div class="rev-v2__summary-row">
              <span>Despesa:</span>
              <strong>{{ expense.description }}</strong>
            </div>
            <div class="rev-v2__summary-row">
              <span>Valor pago:</span>
              <strong>{{ centsToBRL(expense.total_cents) }}</strong>
            </div>
            <div class="rev-v2__summary-row">
              <span>Pago em:</span>
              <strong>{{ formatDate(expense.paid_at) }}</strong>
            </div>
          </div>

          <label class="rev-v2__field">
            <span class="rev-v2__field-label">
              Motivo do estorno <span class="rev-v2__required">*</span>
            </span>
            <textarea
              v-model="reason"
              class="finv2-input"
              rows="3"
              placeholder="Ex.: Pagamento duplicado, valor errado, cancelado pelo fornecedor…"
              autofocus
            />
            <span class="rev-v2__field-hint">Mínimo 3 caracteres. Aparecerá no AuditLog.</span>
          </label>

          <div class="rev-v2__warning">
            <i class="i-lucide-alert-triangle" />
            <span>
              O estorno cria um <strong>lançamento de reversão</strong> no Fluxo de Caixa.
              O lançamento original permanece — não é apagado.
            </span>
          </div>
        </div>

        <footer class="rev-v2__footer">
          <BeclinicButton variant="ghost" color="slate" label="Cancelar" :disabled="submitting" @click="close" />
          <BeclinicButton
            variant="solid"
            color="ruby"
            icon="i-lucide-undo-2"
            label="Confirmar estorno"
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
.rev-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .rev-v2__backdrop { align-items: center; padding: 16px; }
}

.rev-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .rev-v2__modal {
    width: min(480px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.rev-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.rev-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.rev-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--ruby-9)); }
.rev-v2__subtitle { margin: 6px 0 0; font-size: 12px; color: rgb(var(--slate-9)); }

.rev-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.rev-v2__summary {
  padding: 12px 14px;
  background: rgb(var(--slate-2));
  border-radius: 8px;
  display: flex; flex-direction: column; gap: 6px;
}
.rev-v2__summary-row {
  display: flex; justify-content: space-between; align-items: center;
  font-size: 12px;
  color: rgb(var(--slate-10));
  strong { color: rgb(var(--slate-12)); font-weight: 500; }
}

.rev-v2__field { display: flex; flex-direction: column; gap: 6px; }
.rev-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.rev-v2__required { color: rgb(var(--ruby-9)); }
.rev-v2__field-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-style: italic;
}

.rev-v2__warning {
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

.rev-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
