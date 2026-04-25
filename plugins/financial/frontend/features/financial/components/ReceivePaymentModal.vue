<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import bankAccountsApi from '../api/bankAccounts';

const props = defineProps({
  show: { type: Boolean, default: false },
  transaction: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const paymentMethod = ref('pix');
const paidAt = ref(new Date().toISOString().slice(0, 10));
const bankAccountId = ref('');
const bankAccounts = ref([]);
const proofFile = ref(null);
const proofFileName = ref('');
const dragging = ref(false);
const submitting = ref(false);

const PAYMENT_METHODS = [
  { key: 'pix', label: 'PIX', icon: 'i-ph-qr-code' },
  { key: 'dinheiro', label: 'Dinheiro', icon: 'i-ph-money' },
  { key: 'cartao_credito', label: 'Crédito', icon: 'i-ph-credit-card' },
  { key: 'cartao_debito', label: 'Débito', icon: 'i-ph-credit-card' },
  { key: 'transferencia', label: 'Transf.', icon: 'i-ph-arrows-left-right' },
  { key: 'boleto', label: 'Boleto', icon: 'i-ph-receipt' },
];

const CASH_METHODS = ['dinheiro'];

async function loadBankAccounts() {
  try {
    const { data } = await bankAccountsApi.get();
    bankAccounts.value = data.bank_accounts || [];
    // Pré-seleciona a primeira conta se só houver uma
    if (bankAccounts.value.length === 1) {
      bankAccountId.value = bankAccounts.value[0].id;
    }
  } catch {
    bankAccounts.value = [];
  }
}

onMounted(loadBankAccounts);

// Reset when opening
watch(
  () => props.show,
  val => {
    if (val) {
      paymentMethod.value = 'pix';
      paidAt.value = new Date().toISOString().slice(0, 10);
      proofFile.value = null;
      proofFileName.value = '';
      submitting.value = false;
      // Re-seleciona se só houver uma conta
      if (bankAccounts.value.length === 1) {
        bankAccountId.value = bankAccounts.value[0].id;
      } else {
        bankAccountId.value = '';
      }
    }
  }
);

function formatCurrency(v) {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(v || 0);
}

function formatDate(d) {
  if (!d) return '—';
  const [y, m, day] = d.split('-');
  return `${day}/${m}/${y}`;
}

function onFileInput(e) {
  const file = e.target.files?.[0];
  if (!file) return;
  proofFile.value = file;
  proofFileName.value = file.name;
}

function onDrop(e) {
  dragging.value = false;
  const file = e.dataTransfer.files?.[0];
  if (!file) return;
  if (!file.type.match(/(image\/(png|jpeg|jpg|webp)|application\/pdf)/)) return;
  proofFile.value = file;
  proofFileName.value = file.name;
}

function removeFile() {
  proofFile.value = null;
  proofFileName.value = '';
}

const needsBankAccount = computed(
  () => !CASH_METHODS.includes(paymentMethod.value)
);

const canConfirm = computed(() => {
  if (!paymentMethod.value || !paidAt.value || submitting.value) return false;
  if (needsBankAccount.value && !bankAccountId.value) return false;
  return true;
});

async function confirm() {
  if (!canConfirm.value) return;
  submitting.value = true;
  emit('confirm', {
    paymentMethod: paymentMethod.value,
    paidAt: paidAt.value,
    bankAccountId: bankAccountId.value || null,
    proofFile: proofFile.value,
  });
}
</script>

<template>
  <Teleport to="body">
    <Transition name="modal-fade">
      <div v-if="show" class="rp-overlay" @click.self="emit('close')">
        <div class="rp-modal" role="dialog" aria-modal="true">
          <!-- Header -->
          <div class="rp-header">
            <div class="rp-header__icon">
              <span class="i-ph-check-circle" />
            </div>
            <div>
              <h3 class="rp-title">Registrar Pagamento</h3>
              <p class="rp-subtitle">
                Confirme o método e a data do recebimento
              </p>
            </div>
            <button class="rp-close" @click="emit('close')">
              <span class="i-ph-x" />
            </button>
          </div>

          <!-- Transaction info -->
          <div v-if="transaction" class="rp-tx-info">
            <div class="rp-tx-info__row">
              <span class="rp-tx-info__label">Parcela / Título</span>
              <span class="rp-tx-info__value rp-tx-info__value--desc">
                {{ transaction.description || '—' }}
              </span>
            </div>
            <div class="rp-tx-info__row">
              <span class="rp-tx-info__label">Valor</span>
              <span class="rp-tx-info__value rp-tx-info__value--amount">
                {{ formatCurrency(transaction.amount) }}
              </span>
            </div>
            <div class="rp-tx-info__row">
              <span class="rp-tx-info__label">Vencimento</span>
              <span class="rp-tx-info__value">{{
                formatDate(transaction.due_date)
              }}</span>
            </div>
          </div>

          <!-- Payment method grid -->
          <div class="rp-section">
            <label class="rp-label">Método de Pagamento <span class="rp-required">*</span></label>
            <div class="rp-method-grid">
              <button
                v-for="m in PAYMENT_METHODS"
                :key="m.key"
                class="rp-method-btn"
                :class="{ 'rp-method-btn--active': paymentMethod === m.key }"
                type="button"
                @click="paymentMethod = m.key"
              >
                <span class="rp-method-icon" :class="[m.icon]" />
                <span class="rp-method-label">{{ m.label }}</span>
              </button>
            </div>
          </div>

          <!-- Date picker -->
          <div class="rp-section">
            <label class="rp-label"
for="rp-date"
              >Data do Pagamento <span class="rp-required">*</span></label>
            <input
              id="rp-date"
              v-model="paidAt"
              type="date"
              class="rp-date-input"
            />
          </div>

          <!-- Bank Account -->
          <div class="rp-section">
            <label class="rp-label" for="rp-bank-account">
              Conta de Destino
              <span v-if="needsBankAccount" class="rp-required">*</span>
              <span v-else class="rp-optional">(opcional)</span>
            </label>
            <div v-if="!bankAccounts.length" class="rp-bank-empty">
              <span class="i-ph-bank" />
              <span>Nenhuma conta cadastrada. Adicione em
                <strong>Configurações → Contas Bancárias</strong>.</span>
            </div>
            <select
              v-else
              id="rp-bank-account"
              v-model="bankAccountId"
              class="rp-select"
              :class="{
                'rp-select--required': needsBankAccount && !bankAccountId,
              }"
            >
              <option value="">— Selecionar conta —</option>
              <option v-for="ba in bankAccounts" :key="ba.id" :value="ba.id">
                {{ ba.bank_code ? `${ba.bank_code} · ` : '' }}{{ ba.name
                }}{{ ba.bank_name ? ` (${ba.bank_name})` : '' }}
              </option>
            </select>
            <p
              v-if="needsBankAccount && !bankAccountId && bankAccounts.length"
              class="rp-bank-hint"
            >
              Selecione a conta que vai receber este pagamento
            </p>
          </div>

          <!-- Proof upload -->
          <div class="rp-section">
            <label class="rp-label">Comprovante <span class="rp-optional">(opcional)</span></label>
            <div
              v-if="!proofFile"
              class="rp-dropzone"
              :class="{ 'rp-dropzone--active': dragging }"
              @dragover.prevent="dragging = true"
              @dragleave.prevent="dragging = false"
              @drop.prevent="onDrop"
              @click="$refs.fileInput.click()"
            >
              <span class="i-ph-upload-simple rp-dropzone__icon" />
              <p class="rp-dropzone__text">
                Arraste um arquivo ou
                <span class="rp-dropzone__link">clique para selecionar</span>
              </p>
              <p class="rp-dropzone__hint">PDF, PNG ou JPEG — máx. 10 MB</p>
              <input
                ref="fileInput"
                type="file"
                accept=".pdf,.png,.jpg,.jpeg,.webp"
                class="hidden"
                @change="onFileInput"
              />
            </div>

            <div v-else class="rp-proof-file">
              <span class="i-ph-file-check rp-proof-file__icon" />
              <span class="rp-proof-file__name">{{ proofFileName }}</span>
              <button
                class="rp-proof-file__remove"
                type="button"
                @click="removeFile"
              >
                <span class="i-ph-x" />
              </button>
            </div>
          </div>

          <!-- Actions -->
          <div class="rp-actions">
            <button
              class="rp-btn rp-btn--ghost"
              type="button"
              @click="emit('close')"
            >
              Cancelar
            </button>
            <button
              class="rp-btn rp-btn--primary"
              type="button"
              :disabled="!canConfirm"
              @click="confirm"
            >
              <span v-if="submitting" class="i-ph-spinner rp-spin" />
              <span v-else class="i-ph-check-circle" />
              Confirmar Pagamento
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
/* ── Overlay ───────────────────────────────────────────────────────────────── */
.rp-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}

/* ── Modal card ────────────────────────────────────────────────────────────── */
.rp-modal {
  background: #fff;
  border-radius: 16px;
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.18);
  width: 100%;
  max-width: 480px;
  overflow: hidden;
}

/* ── Header ─────────────────────────────────────────────────────────────────── */
.rp-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 20px 24px 16px;
  border-bottom: none !important;
}

.rp-header__icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: rgba(22, 163, 74, 0.1);
  color: #16a34a;
  font-size: 18px;
  flex-shrink: 0;
}

.rp-title {
  font-size: 15px;
  font-weight: 600;
  color: #0f172a;
  margin: 0;
}

.rp-subtitle {
  font-size: 12px;
  color: #64748b;
  margin: 2px 0 0;
}

.rp-close {
  margin-left: auto;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  border: none;
  background: transparent;
  color: #94a3b8;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition:
    background 0.15s,
    color 0.15s;
}

.rp-close:hover {
  background: #f1f5f9;
  color: #475569;
}

/* ── Transaction info ────────────────────────────────────────────────────── */
.rp-tx-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
  background: #f8fafc;
  border: none !important;
  border-radius: 10px;
  padding: 12px 16px;
  margin: 16px 24px 4px;
}

.rp-tx-info__row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.rp-tx-info__label {
  font-size: 11px;
  color: #94a3b8;
  min-width: 88px;
  flex-shrink: 0;
}

.rp-tx-info__value {
  font-size: 13px;
  color: #334155;
  font-weight: 500;
}

.rp-tx-info__value--desc {
  color: #1e293b;
  font-weight: 600;
}

.rp-tx-info__value--amount {
  color: #16a34a;
  font-weight: 700;
}

/* ── Sections ────────────────────────────────────────────────────────────── */
.rp-section {
  padding: 14px 24px 0;
  border-top: none !important;
}

.rp-label {
  display: block;
  font-size: 12px;
  font-weight: 600;
  color: #475569;
  margin-bottom: 8px;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}

.rp-required {
  color: #ef4444;
  margin-left: 2px;
}

.rp-optional {
  color: #94a3b8;
  font-weight: 400;
  text-transform: none;
  letter-spacing: 0;
}

/* ── Payment method grid ─────────────────────────────────────────────────── */
.rp-method-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}

.rp-method-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 5px;
  padding: 10px 8px;
  border-radius: 10px;
  border: none !important;
  box-shadow: none !important;
  background: #f8fafc;
  cursor: pointer;
  transition: all 0.15s ease;
  color: #64748b;
}

.rp-method-btn:hover {
  background: #f1f5f9;
  color: #0f172a;
}

.rp-method-btn--active {
  border: none !important;
  box-shadow: none !important;
  background: #eff6ff;
  color: #2563eb;
}

.rp-method-icon {
  font-size: 20px;
  stroke-width: 1.5px;
  opacity: 0.9;
}

.rp-method-label {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.01em;
}

/* ── Date input ──────────────────────────────────────────────────────────── */
.rp-date-input {
  width: 100%;
  padding: 9px 12px;
  border-radius: 8px;
  border: none !important;
  box-shadow: none !important;
  background: #f8fafc;
  font-size: 14px;
  color: #1e293b;
  outline: none;
  transition: border-color 0.15s;
  box-sizing: border-box;
}

.rp-date-input:focus {
  background: #f1f5f9;
}

/* ── Bank account select ─────────────────────────────────────────────────── */
.rp-select {
  width: 100%;
  padding: 9px 12px;
  border-radius: 8px;
  border: 1.5px solid #e2e8f0;
  background: #f8fafc;
  font-size: 14px;
  color: #1e293b;
  outline: none;
  cursor: pointer;
  transition:
    border-color 0.15s,
    background 0.15s;
  box-sizing: border-box;
  appearance: auto;
}

.rp-select:focus {
  border-color: #2563eb;
  background: #fff;
}

.rp-select--required {
  border-color: #fbbf24;
  background: #fffbeb;
}

.rp-bank-empty {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 8px;
  background: #fef9c3;
  color: #92400e;
  font-size: 12px;
  line-height: 1.5;
}

.rp-bank-hint {
  margin: 5px 0 0;
  font-size: 11px;
  color: #f59e0b;
  font-weight: 500;
}

/* ── Dropzone ────────────────────────────────────────────────────────────── */
.rp-dropzone {
  border: none !important;
  box-shadow: none !important;
  border-radius: 10px;
  padding: 20px 16px;
  text-align: center;
  cursor: pointer;
  transition: all 0.15s;
  background: #f8fafc;
}

.rp-dropzone:hover,
.rp-dropzone--active {
  background: #f1f5f9;
}

.rp-dropzone__icon {
  font-size: 28px;
  color: #94a3b8;
  display: block;
  margin: 0 auto 8px;
}

.rp-dropzone--active .rp-dropzone__icon {
  color: #3b82f6;
}

.rp-dropzone__text {
  font-size: 13px;
  color: #64748b;
  margin: 0 0 4px;
}

.rp-dropzone__link {
  color: #3b82f6;
  font-weight: 600;
}

.rp-dropzone__hint {
  font-size: 11px;
  color: #94a3b8;
  margin: 0;
}

.rp-proof-file {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  background: #f8fafc;
  border: none !important;
  box-shadow: none !important;
  border-radius: 8px;
}

.rp-proof-file__icon {
  font-size: 18px;
  color: #16a34a;
  flex-shrink: 0;
}

.rp-proof-file__name {
  font-size: 13px;
  color: #15803d;
  font-weight: 500;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.rp-proof-file__remove {
  width: 24px;
  height: 24px;
  border-radius: 4px;
  border: none;
  background: transparent;
  color: #64748b;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.rp-proof-file__remove:hover {
  background: #dcfce7;
  color: #16a34a;
}

/* ── Actions ─────────────────────────────────────────────────────────────── */
.rp-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  padding: 20px 24px;
  margin-top: 10px;
  border-top: none !important;
}

.rp-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 9px 18px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s;
  border: none;
}

.rp-btn--ghost {
  background: #f8fafc;
  color: #475569;
  border: none;
}

.rp-btn--ghost:hover {
  background: #f1f5f9;
  color: #0f172a;
}

.rp-btn--primary {
  background: #2563eb;
  color: #fff;
}

.rp-btn--primary:hover:not(:disabled) {
  background: #1d4ed8;
}

.rp-btn--primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* ── Spin ────────────────────────────────────────────────────────────────── */
.rp-spin {
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

/* ── Transition ──────────────────────────────────────────────────────────── */
.modal-fade-enter-active,
.modal-fade-leave-active {
  transition: opacity 0.2s ease;
}

.modal-fade-enter-active .rp-modal,
.modal-fade-leave-active .rp-modal {
  transition:
    transform 0.2s ease,
    opacity 0.2s ease;
}

.modal-fade-enter-from,
.modal-fade-leave-to {
  opacity: 0;
}

.modal-fade-enter-from .rp-modal {
  transform: scale(0.96) translateY(8px);
  opacity: 0;
}
</style>
