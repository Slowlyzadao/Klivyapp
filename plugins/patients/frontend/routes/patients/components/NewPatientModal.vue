<script setup>
import { ref, watch, computed, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import ContactsAPI from 'dashboard/api/contacts';
import wootModalHeader from 'dashboard/components/ModalHeader.vue';
import BaseSelect from '@plugins/patients/frontend/components/BaseSelect.vue';

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
      try {
        const response = await ContactsAPI.search(rawDigits);
        searchResults.value = response.data?.payload || [];
      } catch {
        // ignore
      } finally {
        isSearching.value = false;
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
  showDropdown.value = false;
  searchResults.value = [];
};

const clearContact = () => {
  selectedContact.value = null;
  state.value.contact_id = null;
  state.value.phone = '';
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

  isLoading.value = true;
  try {
    const payload = {
      name: fullName,
      email: state.value.email,
      cpf: state.value.cpf ? state.value.cpf.replace(/\D/g, '') : '',
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
            v-model="state.birthdate"
            class="npm-input"
            type="date"
            :max="new Date().toISOString().split('T')[0]"
            min="1900-01-01"
          />
        </div>

        <BaseSelect
          v-model="state.sex"
          :options="genderOptions"
          label="Sexo / Gênero"
        />
      </div>
    </form>

    <!-- Footer -->
    <div class="npm-footer">
      <button type="button" class="npm-btn-cancel" @click="onClose">
        Cancelar
      </button>
      <button
        type="button"
        class="npm-btn-submit"
        :disabled="isLoading"
        @click="submitPatient"
      >
        <span v-if="isLoading" class="npm-spinner" />
        <span v-else>Criar Paciente</span>
      </button>
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
