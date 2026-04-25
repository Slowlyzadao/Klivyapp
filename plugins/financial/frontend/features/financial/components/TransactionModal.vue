<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import categoriesApi from '../api/categories';
import bankAccountsApi from '../api/bankAccounts';
import patientsApi from '@plugins/patients/frontend/api/patients/index';

const props = defineProps({
  show: { type: Boolean, default: false },
  transaction: { type: Object, default: null },
  entryType: { type: String, default: 'entrada' },
  mode: { type: String, default: 'create' },
});

const emit = defineEmits(['close', 'save']);

const { t } = useI18n();

const categories = ref([]);
const bankAccounts = ref([]);
const saving = ref(false);

function emptyForm() {
  return {
    entry_type: props.entryType,
    description: '',
    amount: '',
    payment_method: '',
    payment_source: '',
    financial_category_id: '',
    bank_account_id: '',
    due_date: new Date().toISOString().slice(0, 10),
    competence_date: '',
    notes: '',
    status: 'pendente',
    patient_id: null,
  };
}

const form = ref(emptyForm());
const isPatientLinked = ref(false);
const patientSearchQuery = ref('');
const patientsList = ref([]);
const showPatientDropdown = ref(false);
const patientSearchWrapper = ref(null);
let searchTimeout = null;

async function searchPatients() {
  showPatientDropdown.value = true;
  if (!patientSearchQuery.value) {
    patientsList.value = [];
    return;
  }

  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(async () => {
    try {
      const res = await patientsApi.get(1, 'name', patientSearchQuery.value);
      patientsList.value = res.data?.payload?.map?.(p => ({ ...p })) || [];
    } catch {
      patientsList.value = [];
    }
  }, 300);
}

function selectPatient(patient) {
  form.value.patient_id = patient.id;
  patientSearchQuery.value = patient.name;
  showPatientDropdown.value = false;
}

function clearPatient() {
  form.value.patient_id = null;
  patientSearchQuery.value = '';
}

const amountDisplay = ref('');

function formatAsBRL(value) {
  const digits = String(value).replace(/\D/g, '');
  if (!digits) return '';
  const cents = parseInt(digits, 10);
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(cents / 100);
}

function onAmountInput(e) {
  const digits = e.target.value.replace(/\D/g, '');
  const cents = parseInt(digits || '0', 10);
  amountDisplay.value = cents ? formatAsBRL(digits) : '';
  form.value.amount = (cents / 100).toFixed(2);
}

watch(
  () => props.show,
  val => {
    if (val) {
      if (props.transaction && props.mode === 'edit') {
        form.value = {
          entry_type: props.transaction.entry_type || props.entryType,
          description: props.transaction.description || '',
          amount: props.transaction.amount || '',
          payment_method: props.transaction.payment_method || '',
          payment_source: props.transaction.payment_source || '',
          financial_category_id: props.transaction.financial_category_id || '',
          bank_account_id: props.transaction.bank_account_id || '',
          due_date: props.transaction.due_date || '',
          competence_date: props.transaction.competence_date || '',
          notes: props.transaction.notes || '',
          status: props.transaction.status || 'pendente',
          patient_id: props.transaction.patient_id || null,
        };

        if (form.value.patient_id) {
          isPatientLinked.value = true;
          patientSearchQuery.value =
            props.transaction.patient_name || 'Paciente selecionado';
        } else {
          isPatientLinked.value = false;
          patientSearchQuery.value = '';
        }

        amountDisplay.value = props.transaction.amount
          ? formatAsBRL(String(Math.round(props.transaction.amount * 100)))
          : '';
      } else {
        form.value = emptyForm();
        form.value.entry_type = props.entryType;
        amountDisplay.value = '';
        isPatientLinked.value = false;
        patientSearchQuery.value = '';
        patientsList.value = [];
      }
    }
  }
);

const isEditing = computed(() => props.mode === 'edit' && props.transaction);
const title = computed(() => {
  if (isEditing.value) return t('FINANCIAL.TRANSACTION_MODAL.EDIT_TITLE');
  return form.value.entry_type === 'entrada'
    ? t('FINANCIAL.TRANSACTION_MODAL.NEW_INCOME')
    : t('FINANCIAL.TRANSACTION_MODAL.NEW_EXPENSE');
});

const filteredCategories = computed(() => {
  const type = form.value.entry_type === 'entrada' ? 'income' : 'expense';
  return categories.value.filter(c => c.category_type === type);
});

const paymentMethods = [
  { value: 'pix', label: 'Pix' },
  { value: 'dinheiro', label: 'Dinheiro' },
  { value: 'cartao_credito', label: 'Cartão Crédito' },
  { value: 'cartao_debito', label: 'Cartão Débito' },
  { value: 'boleto', label: 'Boleto' },
  { value: 'transferencia', label: 'Transferência' },
];

const paymentSources = [
  { value: 'particular', label: t('FINANCIAL.TRANSACTION_MODAL.SOURCE_PARTICULAR') },
  { value: 'convenio', label: t('FINANCIAL.TRANSACTION_MODAL.SOURCE_CONVENIO') },
  { value: 'plano', label: t('FINANCIAL.TRANSACTION_MODAL.SOURCE_PLANO') },
  { value: 'outro', label: t('FINANCIAL.TRANSACTION_MODAL.SOURCE_OUTRO') },
];

async function loadOptions() {
  try {
    const [catRes, bankRes] = await Promise.all([
      categoriesApi.get(),
      bankAccountsApi.get(),
    ]);
    categories.value = catRes.data?.categories || [];
    bankAccounts.value = bankRes.data?.bank_accounts || [];
  } catch {
    categories.value = [];
    bankAccounts.value = [];
  }
}

function handleClickOutside(event) {
  if (
    patientSearchWrapper.value &&
    !patientSearchWrapper.value.contains(event.target)
  ) {
    showPatientDropdown.value = false;
  }
}

onMounted(() => {
  loadOptions();
  document.addEventListener('click', handleClickOutside);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
});

function close() {
  emit('close');
}

async function save() {
  if (!form.value.description || !form.value.amount) return;
  saving.value = true;
  try {
    const payload = { ...form.value };
    if (!payload.competence_date) {
      const dd = payload.due_date || new Date().toISOString().slice(0, 10);
      payload.competence_date = dd.slice(0, 7) + '-01';
    }
    payload.origin = 'manual';
    emit('save', {
      payload,
      id: props.transaction?.id,
      isEditing: isEditing.value,
    });
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="txn-modal-overlay" @click.self="close">
      <div class="txn-modal">
        <div class="txn-modal__header">
          <h2 class="txn-modal__title">{{ title }}</h2>
          <button class="txn-modal__close" @click="close">
            <span class="i-lucide-x" />
          </button>
        </div>

        <div class="txn-modal__body">
          <!-- Entry type toggle (only on create) -->
          <div v-if="!isEditing" class="txn-type-toggle">
            <button
              class="txn-type-btn"
              :class="{
                'txn-type-btn--active txn-type-btn--income':
                  form.entry_type === 'entrada',
              }"
              @click="form.entry_type = 'entrada'"
            >
              <span class="i-lucide-arrow-down-circle" />
              {{ t('FINANCIAL.TRANSACTION_MODAL.INCOME') }}
            </button>
            <button
              class="txn-type-btn"
              :class="{
                'txn-type-btn--active txn-type-btn--expense':
                  form.entry_type === 'saida',
              }"
              @click="form.entry_type = 'saida'"
            >
              <span class="i-lucide-arrow-up-circle" />
              {{ t('FINANCIAL.TRANSACTION_MODAL.EXPENSE') }}
            </button>
          </div>

          <!-- Description -->
          <div class="txn-field">
            <label class="txn-label">{{
              t('FINANCIAL.TRANSACTION_MODAL.DESCRIPTION')
            }}</label>
            <input
              v-model="form.description"
              type="text"
              class="txn-input"
              :placeholder="
                t('FINANCIAL.TRANSACTION_MODAL.DESCRIPTION_PLACEHOLDER')
              "
            />
          </div>

          <!-- Amount + Payment Method + Source -->
          <div class="txn-form-row">
            <div class="txn-field">
              <label class="txn-label">{{
                t('FINANCIAL.TRANSACTION_MODAL.AMOUNT')
              }}</label>
              <input
                :value="amountDisplay"
                type="text"
                inputmode="numeric"
                class="txn-input"
                :placeholder="
                  t('FINANCIAL.TRANSACTION_MODAL.AMOUNT_PLACEHOLDER')
                "
                @input="onAmountInput"
              />
            </div>
            <div class="txn-field">
              <label class="txn-label">{{
                t('FINANCIAL.TRANSACTION_MODAL.PAYMENT_METHOD')
              }}</label>
              <select v-model="form.payment_method" class="txn-select">
                <option value="">—</option>
                <option
                  v-for="pm in paymentMethods"
                  :key="pm.value"
                  :value="pm.value"
                >
                  {{ pm.label }}
                </option>
              </select>
            </div>
          </div>

          <!-- Origem da receita (apenas para entradas) -->
          <div v-if="form.entry_type === 'entrada'" class="txn-field">
            <label class="txn-label">{{
              t('FINANCIAL.TRANSACTION_MODAL.PAYMENT_SOURCE')
            }}</label>
            <select v-model="form.payment_source" class="txn-select">
              <option value="">—</option>
              <option
                v-for="src in paymentSources"
                :key="src.value"
                :value="src.value"
              >
                {{ src.label }}
              </option>
            </select>
          </div>

          <!-- Category + Bank Account -->
          <div class="txn-form-row">
            <div class="txn-field">
              <label class="txn-label">{{
                t('FINANCIAL.TRANSACTION_MODAL.CATEGORY')
              }}</label>
              <select v-model="form.financial_category_id" class="txn-select">
                <option value="">
                  {{ t('FINANCIAL.TRANSACTION_MODAL.NO_CATEGORY') }}
                </option>
                <option
                  v-for="c in filteredCategories"
                  :key="c.id"
                  :value="c.id"
                >
                  {{ c.name }}
                </option>
              </select>
            </div>
            <div class="txn-field">
              <label class="txn-label">{{
                t('FINANCIAL.TRANSACTION_MODAL.BANK_ACCOUNT')
              }}</label>
              <select v-model="form.bank_account_id" class="txn-select">
                <option value="">—</option>
                <option v-for="b in bankAccounts" :key="b.id" :value="b.id">
                  {{ b.name }}
                </option>
              </select>
            </div>
          </div>

          <!-- Patient Link -->
          <div class="txn-form-row">
            <div class="txn-field">
              <label class="txn-label">Vincular a um paciente?</label>
              <select
                v-model="isPatientLinked"
                class="txn-select"
                @change="!isPatientLinked && clearPatient()"
              >
                <option :value="false">Não</option>
                <option :value="true">Sim</option>
              </select>
            </div>

            <div ref="patientSearchWrapper" class="txn-field relative">
              <div class="flex items-center justify-between w-full">
                <label
                  class="txn-label !mb-0 whitespace-nowrap"
                  :class="{ 'opacity-50': !isPatientLinked }"
                  >Buscar Paciente</label
                >

                <!-- Selected tag -->
                <div
                  v-if="form.patient_id && !showPatientDropdown"
                  class="inline-flex items-center gap-1 px-1.5 py-0.5 bg-green-50 text-green-700 text-[10px] uppercase tracking-wide font-bold rounded shrink-0"
                >
                  <span class="i-lucide-user w-3 h-3" />
                  Vinculado
                </div>
              </div>

              <input
                v-model="patientSearchQuery"
                type="text"
                class="txn-input"
                :class="{
                  'bg-slate-50 cursor-not-allowed opacity-60': !isPatientLinked,
                }"
                :disabled="!isPatientLinked"
                placeholder="Digite o nome do paciente..."
                @input="searchPatients"
                @focus="searchPatients"
              />

              <div
                v-if="
                  isPatientLinked && showPatientDropdown && patientsList.length
                "
                class="absolute top-full z-10 w-full mt-1 bg-white border border-slate-200 rounded-md shadow-lg max-h-48 overflow-auto"
              >
                <div
                  v-for="p in patientsList"
                  :key="p.id"
                  class="px-4 py-2 hover:bg-slate-50 cursor-pointer text-sm text-slate-700 font-medium"
                  @click="selectPatient(p)"
                >
                  {{ p.name }}
                </div>
              </div>
            </div>
          </div>

          <!-- Due date + Status -->
          <div class="txn-form-row">
            <div class="txn-field">
              <label class="txn-label">{{
                t('FINANCIAL.TRANSACTION_MODAL.DUE_DATE')
              }}</label>
              <input v-model="form.due_date" type="date" class="txn-input" />
            </div>
            <div class="txn-field">
              <label class="txn-label">{{
                t('FINANCIAL.TRANSACTION_MODAL.STATUS')
              }}</label>
              <select v-model="form.status" class="txn-select">
                <option value="pendente">
                  {{ t('FINANCIAL.TRANSACTION_MODAL.STATUS_PENDING') }}
                </option>
                <option v-if="form.entry_type === 'entrada'" value="recebido">
                  {{ t('FINANCIAL.TRANSACTION_MODAL.STATUS_RECEIVED') }}
                </option>
                <option v-if="form.entry_type === 'saida'" value="pago">
                  {{ t('FINANCIAL.TRANSACTION_MODAL.STATUS_PAID') }}
                </option>
              </select>
            </div>
          </div>

          <!-- Notes -->
          <div class="txn-field">
            <label class="txn-label">{{
              t('FINANCIAL.TRANSACTION_MODAL.NOTES')
            }}</label>
            <textarea v-model="form.notes" class="txn-textarea" rows="2" />
          </div>
        </div>

        <div class="txn-modal__footer">
          <button class="txn-btn txn-btn--cancel" @click="close">
            {{ t('FINANCIAL.TRANSACTION_MODAL.CANCEL') }}
          </button>
          <button
            class="txn-btn txn-btn--save"
            :disabled="saving || !form.description || !form.amount"
            @click="save"
          >
            {{
              saving
                ? t('FINANCIAL.TRANSACTION_MODAL.SAVING')
                : t('FINANCIAL.TRANSACTION_MODAL.SAVE')
            }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
