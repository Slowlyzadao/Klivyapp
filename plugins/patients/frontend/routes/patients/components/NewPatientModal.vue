<script setup>
import { ref, watch, computed, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import ContactsAPI from 'dashboard/api/contacts';
import wootModalHeader from 'dashboard/components/ModalHeader.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  formatDateBR,
  brToIsoDate,
  maskDateBR,
} from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import { isValidCPF, onlyDigits } from '@plugins/beclinic_core/frontend/helpers/cpfHelpers';
import {
  isValidEmail,
  isValidBrazilianPhone,
} from '@plugins/beclinic_core/frontend/helpers/contactValidators';

const emit = defineEmits(['close', 'success']);

const isLoading = ref(false);
const skipNextSearch = ref(false);

const state = ref({
  first_name: '',
  last_name: '',
  email: '',
  phone: '',
  cpf: '',
  birthdate: '',
  sex: 'nao_informado',
  contact_id: null,
});

const selectedContact = ref(null);
const searchResults = ref([]);
const isSearching = ref(false);
const showDropdown = ref(false);
let searchTimeout = null;
// Contador monotônico — cada chamada de busca incrementa e captura seu id.
// Quando a resposta volta, descartamos se não for a mais recente. Resolve
// race condition: digitar rápido pode disparar 3 requests; só a última deve
// popular o dropdown.
let latestSearchId = 0;

// ── Opções de Gênero ────────────────────────────────────────────────────────
const genderOptions = [
  { label: 'Não Informado', value: 'nao_informado' },
  { label: 'Masculino', value: 'masculino' },
  { label: 'Feminino', value: 'feminino' },
];

// ── Phone ─────────────────────────────────────────────────────────────────────
const onPhoneInputFocus = () => {
  if (!selectedContact.value) {
    const digits = String(state.value.phone || '').replace(/\D/g, '');
    if (digits.length >= 2) showDropdown.value = true;
  }
};

const onPhoneInputBlur = () => {
  setTimeout(() => {
    showDropdown.value = false;
  }, 200);
};

const onPhoneInput = () => {
  if (selectedContact.value) {
    selectedContact.value = null;
    state.value.contact_id = null;
  }
};

watch(
  () => state.value.phone,
  newVal => {
    if (newVal) {
      let value = String(newVal).replace(/\D/g, '');
      if (value.startsWith('55')) value = value.slice(2);
      if (value.length > 11) value = value.slice(0, 11);

      let formatted = value;
      if (value.length > 10) {
        formatted = value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
      } else if (value.length > 6) {
        formatted = value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
      } else if (value.length > 2) {
        formatted = value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
      } else if (value.length > 0) {
        formatted = value.replace(/(\d{0,2})/, '($1');
      }

      if (newVal !== formatted) {
        state.value.phone = formatted;
        return;
      }
    }

    if (skipNextSearch.value) {
      skipNextSearch.value = false;
      return;
    }

    clearTimeout(searchTimeout);
    const rawDigits = String(newVal || '').replace(/\D/g, '');
    if (!rawDigits || rawDigits.length < 2) {
      searchResults.value = [];
      showDropdown.value = false;
      return;
    }

    showDropdown.value = true;
    isSearching.value = true;

    searchTimeout = setTimeout(async () => {
      latestSearchId += 1;
      const requestId = latestSearchId;
      try {
        const response = await ContactsAPI.search(rawDigits);
        // Descarta resposta obsoleta — usuário continuou digitando, outra
        // request mais recente está em vôo (ou já chegou e populou os results).
        if (requestId !== latestSearchId) return;
        searchResults.value = response.data?.payload || [];
      } catch (error) {
        if (requestId !== latestSearchId) return;
        // Best-effort: busca de contato é autocomplete, não bloqueia o
        // cadastro. Sem alert pra não quebrar o fluxo de digitação.
        // eslint-disable-next-line no-console
        console.error('[NewPatient] Falha ao buscar contatos', error);
      } finally {
        if (requestId === latestSearchId) isSearching.value = false;
      }
    }, 400);
  }
);

// ── CPF ───────────────────────────────────────────────────────────────────────
watch(
  () => state.value.cpf,
  newVal => {
    if (!newVal) return;
    let value = String(newVal).replace(/\D/g, '');
    if (value.length > 11) value = value.slice(0, 11);

    let formatted = value;
    if (value.length > 9) {
      formatted = value.replace(
        /(\d{3})(\d{3})(\d{3})(\d{1,2})/,
        '$1.$2.$3-$4'
      );
    } else if (value.length > 6) {
      formatted = value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
    } else if (value.length > 3) {
      formatted = value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
    }

    if (newVal !== formatted) state.value.cpf = formatted;
  }
);

// ── Contact selection ─────────────────────────────────────────────────────────
// Contatos no Chatwoot têm `additional_attributes` (JSONB) e `custom_attributes`
// onde campos como CPF, RG e data de nascimento ficam quando coletados via
// formulário ou conversa. Tentamos pré-preencher pra evitar redigitação.
const pickContactField = (contact, ...keys) => {
  const sources = [
    contact,
    contact?.additional_attributes,
    contact?.custom_attributes,
  ].filter(Boolean);
  for (const src of sources) {
    for (const key of keys) {
      if (src[key]) return src[key];
    }
  }
  return null;
};

const selectContact = contact => {
  skipNextSearch.value = true;
  selectedContact.value = contact;
  state.value.contact_id = contact.id;

  if (contact.name && !state.value.first_name && !state.value.last_name) {
    const parts = contact.name.trim().split(' ');
    state.value.first_name = parts[0] || '';
    state.value.last_name = parts.slice(1).join(' ') || '';
  }

  state.value.email = contact.email || state.value.email;
  state.value.phone = contact.phone_number || state.value.phone;

  // Auto-fill de CPF (se contato tem; respeita CPF já digitado pelo usuário)
  if (!state.value.cpf) {
    const contactCpf = pickContactField(contact, 'cpf', 'CPF');
    if (contactCpf) state.value.cpf = String(contactCpf);
  }

  // Auto-fill de data de nascimento (formato ISO ou DD/MM/YYYY ambos aceitos)
  if (!state.value.birthdate) {
    const contactBirth = pickContactField(
      contact,
      'birthdate',
      'date_of_birth',
      'data_nascimento'
    );
    if (contactBirth) {
      // Aceita ISO ('1985-03-15') ou tenta normalizar BR ('15/03/1985')
      const iso = String(contactBirth).match(/^\d{4}-\d{2}-\d{2}$/)
        ? contactBirth
        : brToIsoDate(contactBirth);
      if (iso) {
        state.value.birthdate = iso;
        birthdateInputDisplay.value = formatDateBR(iso);
      }
    }
  }

  showDropdown.value = false;
  searchResults.value = [];
};

const clearContact = () => {
  selectedContact.value = null;
  state.value.contact_id = null;
  state.value.phone = '';
};

// ── Data de Nascimento — input mascarado DD/MM/AAAA ─────────────────────────
// Backend armazena ISO (YYYY-MM-DD); convertemos no frontend. Mesmo padrão da
// aba Cadastro (RegistrationTab) — UX melhor que calendário pra digitar
// ano de nascimento.
const birthdateInputDisplay = ref('');

const handleBirthdateInput = event => {
  const masked = maskDateBR(event.target.value);
  birthdateInputDisplay.value = masked;
  event.target.value = masked;
  if (masked.length === 10) {
    const iso = brToIsoDate(masked);
    if (iso) {
      state.value.birthdate = iso;
    }
  } else if (masked.length === 0) {
    state.value.birthdate = '';
  }
};

const handleBirthdateBlur = () => {
  if (!state.value.birthdate) {
    birthdateInputDisplay.value = '';
  } else {
    birthdateInputDisplay.value = formatDateBR(state.value.birthdate);
  }
};

// ── Avatar helpers ────────────────────────────────────────────────────────────
const AVATAR_COLORS = [
  '#6366f1',
  '#8b5cf6',
  '#ec4899',
  '#f43f5e',
  '#f97316',
  '#eab308',
  '#22c55e',
  '#14b8a6',
  '#06b6d4',
  '#3b82f6',
];
const getContactColor = name => {
  if (!name) return AVATAR_COLORS[0];
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    // eslint-disable-next-line no-bitwise
    hash = name.charCodeAt(i) + (hash * 32 - hash);
  }
  return AVATAR_COLORS[Math.abs(hash) % AVATAR_COLORS.length];
};
const getInitial = name => (name || '?')[0].toUpperCase();

// ── Submit ────────────────────────────────────────────────────────────────────
onBeforeUnmount(() => clearTimeout(searchTimeout));

const onClose = () => emit('close');

const submitPatient = async () => {
  if (!state.value.first_name.trim()) {
    useAlert('O primeiro nome é obrigatório.');
    return;
  }

  const fullName = `${state.value.first_name} ${state.value.last_name}`.trim();

  if (fullName.length < 2) {
    useAlert('O nome do paciente deve ter pelo menos 2 caracteres.');
    return;
  }

  // CPF é opcional, mas se preenchido precisa ser válido (algoritmo de
  // dígito verificador). Bloqueia 000.000.000-00 e CPFs com erro de digitação.
  if (state.value.cpf && !isValidCPF(state.value.cpf)) {
    useAlert('CPF inválido. Verifique os dígitos.');
    return;
  }

  // E-mail e telefone são opcionais, mas se preenchidos precisam ter formato
  // válido — evita dados que quebrariam envio futuro de e-mail/SMS.
  if (state.value.email && !isValidEmail(state.value.email)) {
    useAlert('E-mail inválido. Inclua um domínio completo, ex.: nome@dominio.com.');
    return;
  }
  if (state.value.phone && !isValidBrazilianPhone(state.value.phone)) {
    useAlert('Telefone inválido. Informe DDD + número (10 ou 11 dígitos).');
    return;
  }

  isLoading.value = true;
  try {
    const payload = {
      name: fullName,
      email: state.value.email,
      cpf: state.value.cpf ? onlyDigits(state.value.cpf) : '',
      birthdate: state.value.birthdate,
      sex: state.value.sex,
      contact_id: state.value.contact_id,
      phone: state.value.phone
        ? `+55${state.value.phone.replace(/\D/g, '')}`
        : '',
    };

    const response = await PatientsAPI.create(payload);
    useAlert('Paciente criado com sucesso!');
    emit('success', response.data?.payload || response.data);
    onClose();
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        error.message ||
        'Erro ao criar paciente.'
    );
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="npm-wrap">
    <!-- Header do modal (woot-modal já exibe botão ×) -->
    <wootModalHeader
      header-title="Novo Paciente"
      header-content="Preencha os dados básicos do paciente"
    />

    <!-- Form -->
    <form class="npm-body" @submit.prevent="submitPatient">

      <!-- Nome -->
      <div class="npm-row-2">
        <div class="npm-field">
          <label class="npm-label">
            Primeiro Nome <span class="npm-required">*</span>
          </label>
          <input
            v-model="state.first_name"
            class="npm-input"
            type="text"
            placeholder="Ex: João"
            required
            autocomplete="off"
          />
        </div>
        <div class="npm-field">
          <label class="npm-label">Sobrenome</label>
          <input
            v-model="state.last_name"
            class="npm-input"
            type="text"
            placeholder="da Silva"
            autocomplete="off"
          />
        </div>
      </div>

      <!-- E-mail -->
      <div class="npm-field">
        <label class="npm-label">E-mail</label>
        <input
          v-model="state.email"
          class="npm-input"
          type="email"
          placeholder="joao@email.com"
          autocomplete="email"
        />
      </div>

      <div class="npm-row-2">
        <!-- Phone -->
        <div class="npm-field npm-field--relative">
          <label class="npm-label">Celular / WhatsApp</label>

          <!-- Chip de contato selecionado -->
          <div v-if="selectedContact" class="npm-chip">
            <span
              v-if="selectedContact.avatar_url"
              class="npm-chip-avatar npm-chip-avatar--img"
            >
              <img
                :src="selectedContact.avatar_url"
                :alt="selectedContact.name"
              />
            </span>
            <span
              v-else
              class="npm-chip-avatar"
              :style="{ background: getContactColor(selectedContact.name) }"
            >
              {{ getInitial(selectedContact.name) }}
            </span>
            <span class="npm-chip-name">{{ selectedContact.name }}</span>
            <button type="button" class="npm-chip-clear" @click="clearContact">
              ×
            </button>
          </div>

          <input
            v-else
            v-model="state.phone"
            class="npm-input"
            type="text"
            placeholder="(11) 98888-0000"
            autocomplete="off"
            @focus="onPhoneInputFocus"
            @blur="onPhoneInputBlur"
            @input="onPhoneInput"
          />

          <!-- Dropdown de contatos -->
          <div
            v-if="showDropdown && (isSearching || searchResults.length > 0)"
            class="npm-dropdown"
          >
            <div v-if="isSearching" class="npm-dropdown-loading">
              Buscando...
            </div>
            <ul v-else class="npm-dropdown-list">
              <li
                v-for="contact in searchResults"
                :key="contact.id"
                class="npm-dropdown-item"
                @mousedown.prevent="selectContact(contact)"
              >
                <span
                  v-if="contact.avatar_url"
                  class="npm-item-avatar npm-item-avatar--img"
                >
                  <img :src="contact.avatar_url" :alt="contact.name" />
                </span>
                <span
                  v-else
                  class="npm-item-avatar"
                  :style="{ background: getContactColor(contact.name) }"
                >
                  {{ getInitial(contact.name) }}
                </span>
                <div class="npm-item-info">
                  <span class="npm-item-name">{{
                    contact.name || 'Sem nome'
                  }}</span>
                  <span class="npm-item-phone">{{ contact.phone_number }}</span>
                </div>
              </li>
            </ul>
          </div>
        </div>

        <!-- CPF -->
        <div class="npm-field">
          <label class="npm-label">CPF</label>
          <input
            v-model="state.cpf"
            class="npm-input"
            type="text"
            placeholder="000.000.000-00"
            maxlength="14"
            autocomplete="off"
          />
        </div>
      </div>

      <div class="npm-row-2">
        <div class="npm-field">
          <label class="npm-label">Data de Nascimento</label>
          <input
            :value="birthdateInputDisplay"
            type="text"
            inputmode="numeric"
            class="npm-input"
            placeholder="DD/MM/AAAA"
            maxlength="10"
            autocomplete="bday"
            @input="handleBirthdateInput"
            @blur="handleBirthdateBlur"
          />
        </div>

        <div class="npm-field">
          <label class="npm-label">Sexo / Gênero</label>
          <FormSelect
            v-model="state.sex"
            :options="genderOptions"
            placeholder="Selecione"
          />
        </div>
      </div>
    </form>

    <!-- Footer -->
    <div class="npm-footer">
      <BeclinicButton
        type="button"
        variant="ghost"
        color="slate"
        label="Cancelar"
        @click="onClose"
      />
      <BeclinicButton
        type="button"
        variant="solid"
        color="blue"
        label="Criar Paciente"
        :is-loading="isLoading"
        :disabled="isLoading"
        @click="submitPatient"
      />
    </div>
  </div>
</template>

<style scoped>
/* ── Wrapper — sem background próprio; o woot-modal já fornece o container ── */
.npm-wrap {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
}

/* ── Body / Form ─────────────────────────────────── */
.npm-body {
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: 100%;
  padding: 16px 22px;
  flex: 1;
  overflow-y: auto;
}



/* Grid 2 colunas */
.npm-row-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

/* Field */
.npm-field {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.npm-field--relative {
  position: relative;
}

/* Label */
.npm-label {
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-11));
}
.npm-required {
  color: #f87171;
}

.npm-input {
  width: 100%;
  box-sizing: border-box;
  padding: 0.375rem 0.75rem;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 0.75rem;
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-12));
  font-size: 0.875rem;
  min-height: 2.5rem;
  font-family: inherit;
  outline: none;
  transition: all 0.2s ease-in-out;
}
.npm-input:focus {
  border-color: rgba(var(--blue-9), 0.5);
  box-shadow: 0 0 0 1px rgba(var(--blue-9), 0.5);
  background: rgb(var(--slate-1));
}
.npm-input::placeholder {
  color: rgb(var(--slate-8));
}

/* Select */
.npm-select {
  appearance: none;
  -webkit-appearance: none;
  cursor: pointer;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 24 24' stroke-width='1.5' stroke='%2394a3b8'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M8.25 15 12 18.75 15.75 15m-7.5-6L12 5.25 15.75 9' /%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 0.75rem center;
  background-size: 1.25rem 1.25rem;
  padding-right: 2.5rem;
}

/* ── Contact chip ────────────────────────────────── */
.npm-chip {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  border: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
  border-radius: 0.75rem;
  width: 100%;
  box-sizing: border-box;
}
.npm-chip-avatar {
  width: 24px;
  height: 24px;
  min-width: 24px;
  border-radius: 50%;
  font-size: 10px;
  font-weight: 700;
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}
.npm-chip-avatar--img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.npm-chip-name {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.npm-chip-clear {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 4px;
  border: none;
  background: transparent;
  color: rgb(var(--slate-9));
  font-size: 16px;
  line-height: 1;
  cursor: pointer;
  padding: 0;
  flex-shrink: 0;
  transition:
    background 0.12s,
    color 0.12s;
}
.npm-chip-clear:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}

/* ── Contact search dropdown ─────────────────────── */
.npm-dropdown {
  position: absolute;
  top: calc(100% + 2px);
  left: 0;
  right: 0;
  z-index: 50;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
  overflow: hidden;
  max-height: 190px;
  overflow-y: auto;
}
.npm-dropdown-loading {
  padding: 10px 14px;
  font-size: 13px;
  color: rgb(var(--slate-9));
}
.npm-dropdown-list {
  list-style: none;
  margin: 0;
  padding: 4px;
}
.npm-dropdown-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.1s;
}
.npm-dropdown-item:hover {
  background: rgb(var(--slate-3));
}
.npm-item-avatar {
  width: 28px;
  height: 28px;
  min-width: 28px;
  border-radius: 50%;
  font-size: 11px;
  font-weight: 700;
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}
.npm-item-avatar--img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.npm-item-info {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
}
.npm-item-name {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.npm-item-phone {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* ── Footer ─────────────────────────────────────── */
.npm-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 12px 22px 18px;
  border-top: 1px solid rgb(var(--slate-4));
}

.npm-btn-cancel {
  display: inline-flex;
  align-items: center;
  background: transparent;
  color: rgb(var(--slate-11));
  border: 1px solid rgb(var(--slate-4));
  padding: 8px 16px;
  border-radius: 0.75rem;
  font-weight: 500;
  font-size: 14px;
  cursor: pointer;
  transition: background 0.15s;
}
.npm-btn-cancel:hover {
  background: rgb(var(--slate-3));
}

.npm-btn-submit {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  background: #3b82f6;
  color: #fff;
  border: none;
  padding: 8px 18px;
  border-radius: 0.75rem;
  font-weight: 500;
  font-size: 14px;
  cursor: pointer;
  min-width: 120px;
  transition: background 0.15s;
}
.npm-btn-submit:hover:not(:disabled) {
  background: #2563eb;
}
.npm-btn-submit:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* Spinner */
.npm-spinner {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.35);
  border-top-color: #fff;
  border-radius: 50%;
  animation: npm-spin 0.6s linear infinite;
  display: inline-block;
}
@keyframes npm-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
