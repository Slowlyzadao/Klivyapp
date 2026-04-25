<script setup>
// eslint-disable-next-line no-unused-vars
import { inject, ref, watch, onBeforeUnmount } from 'vue';
import ContactsAPI from 'dashboard/api/contacts';

const patient = inject('patient');
const formatDate = inject('formatDate');
const saveRegistration = inject('saveRegistration');
const regSections = inject('regSections');
const toggleRegSection = inject('toggleRegSection');
const editFirstName = inject('editFirstName');
const editLastName = inject('editLastName');
const avatarInputRef = inject('avatarInputRef');
const triggerAvatarUpload = inject('triggerAvatarUpload');
const openCameraModal = inject('openCameraModal');
const handleAvatarUpload = inject('handleAvatarUpload');
const getInitials = inject('getInitials');
const formatCpfDisplay = inject('formatCpfDisplay');
const handleCpfInput = inject('handleCpfInput');
const formatRgDisplay = inject('formatRgDisplay');
const handleRgInput = inject('handleRgInput');
const formatPhoneDisplay = inject('formatPhoneDisplay');
const handlePhoneInput = inject('handlePhoneInput');
const handleAlternativePhoneInput = inject('handleAlternativePhoneInput');
const searchCep = inject('searchCep');

const searchResults = ref([]);
const isSearching = ref(false);
const showDropdown = ref(false);
const skipNextSearch = ref(false);
let searchTimeout = null;

const onPhoneInputFocus = () => {
  const digits = String(patient.value.phone || '').replace(/\D/g, '');
  if (digits.length >= 2) showDropdown.value = true;
};

const onPhoneInputBlur = () => {
  setTimeout(() => {
    showDropdown.value = false;
  }, 200);
};

// Quando o usuário digita (o input real chama handlePhoneInput do Record.vue, mudando patient.value.phone)
watch(
  () => patient.value.phone,
  newVal => {
    // Limpa o contact_id se o usuário alterar o telefone manualmente
    // patient.value.contact_id = null; // Omitimos isso para não ficar nulo ao carregar

    if (skipNextSearch.value) {
      skipNextSearch.value = false;
      return;
    }

    clearTimeout(searchTimeout);
    // patient.value.phone é salvo como '+55XXXXXXXXX' pelo handlePhoneInput
    // Removemos os dígitos do país (55) antes de buscar
    let rawDigits = String(newVal || '').replace(/\D/g, '');
    if (rawDigits.startsWith('55') && rawDigits.length > 2)
      rawDigits = rawDigits.slice(2);

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

onBeforeUnmount(() => clearTimeout(searchTimeout));

const selectContact = contact => {
  skipNextSearch.value = true;
  patient.value.contact_id = contact.id;

  let value = String(contact.phone_number || '').replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);

  // Format phone automatically when selected
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

  patient.value.phone = formatted;

  if (contact.email && !patient.value.email) {
    patient.value.email = contact.email;
  }

  showDropdown.value = false;
  searchResults.value = [];
};

const getContactColor = name => {
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
  if (!name) return AVATAR_COLORS[0];
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    hash = name.charCodeAt(i) + (hash * 32 - hash);
  }
  return AVATAR_COLORS[Math.abs(hash) % AVATAR_COLORS.length];
};
const getInitial = name => (name || '?')[0].toUpperCase();
</script>

<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header do Cadastro Progressivo -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">Ficha Cadastral</h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Preenchimento progressivo — salve quando quiser.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs text-slate-500"
          >Última alteração: {{ formatDate(patient.updated_at) }}</span
        >
        <button
          class="btn-primary flex items-center gap-2"
          @click="saveRegistration"
        >
          <i class="i-lucide-save w-4 h-4" />
          Salvar
        </button>
      </div>
    </div>

    <!-- Form layout -->
    <div class="reg-form-grid">
      <!-- ── SEÇÃO 1: DADOS PESSOAIS ── -->
      <div class="reg-section">
        <button
          class="reg-section-toggle"
          @click="toggleRegSection('personal')"
        >
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-blue">
              <i class="i-lucide-user w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Dados Pessoais</span>
              <span class="reg-section-subtitle"
                >Nome, nascimento, documento</span
              >
            </div>
          </div>
          <i
            class="i-lucide-chevron-down w-4 h-4 reg-chevron"
            :class="{ 'reg-chevron-open': regSections.personal }"
          />
        </button>

        <div v-if="regSections.personal" class="reg-section-body">
          <!-- Avatar Upload -->
          <div class="reg-avatar-row">
            <div class="reg-avatar-wrapper" @click="triggerAvatarUpload">
              <img
                v-if="patient.avatar_url"
                :src="patient.avatar_url"
                class="reg-avatar-img"
                alt="Avatar do paciente"
              />
              <div v-else class="reg-avatar-placeholder">
                {{ getInitials(patient.name) }}
              </div>
              <div class="reg-avatar-overlay">
                <i class="i-lucide-camera w-5 h-5" />
              </div>
            </div>
            <div class="reg-avatar-info">
              <p class="text-sm font-medium text-slate-200">Foto de Perfil</p>
              <p class="text-xs text-slate-500 mt-0.5">
                JPG ou PNG · máx. 15MB
              </p>
              <div class="flex gap-2 mt-3">
                <button
                  class="btn-secondary btn-xs flex items-center gap-1.5"
                  @click.stop="openCameraModal"
                >
                  <i class="i-lucide-camera w-3.5 h-3.5" /> Câmera
                </button>
                <button
                  class="btn-secondary btn-xs flex items-center gap-1.5"
                  @click.stop="triggerAvatarUpload"
                >
                  <i class="i-lucide-upload w-3.5 h-3.5" /> Upload
                </button>
              </div>
              <input
                ref="avatarInputRef"
                type="file"
                class="hidden"
                accept="image/jpeg, image/png, image/gif"
                @change="handleAvatarUpload"
              />
            </div>
          </div>

          <div class="reg-divider" />

          <div class="reg-field-grid-3">
            <div class="form-group">
              <label>Primeiro Nome <span class="reg-required">*</span></label>
              <input
                v-model="editFirstName"
                type="text"
                class="form-input"
                placeholder="Gabriel"
              />
            </div>
            <div class="form-group">
              <label>Sobrenome</label>
              <input
                v-model="editLastName"
                type="text"
                class="form-input"
                placeholder="Fernandes"
              />
            </div>
            <div class="form-group">
              <label>Nome Social</label>
              <input type="text" class="form-input" placeholder="Opcional" />
            </div>
          </div>

          <div class="reg-field-grid-3">
            <div class="form-group">
              <label
                >Data de Nascimento <span class="reg-required">*</span></label
              >
              <input
                v-model="patient.birthdate"
                type="date"
                class="form-input"
                :max="new Date().toISOString().split('T')[0]"
                min="1900-01-01"
              />
            </div>
            <div class="form-group">
              <label>Sexo <span class="reg-required">*</span></label>
              <select v-model="patient.sex" class="form-input">
                <option value="feminino">Feminino</option>
                <option value="masculino">Masculino</option>
                <option value="outro">Outro</option>
                <option value="nao_informado">Não Informado</option>
              </select>
            </div>
            <div class="form-group">
              <label>Estado Civil</label>
              <select v-model="patient.marital_status" class="form-input">
                <option value="solteiro">Solteiro(a)</option>
                <option value="casado">Casado(a)</option>
                <option value="divorciado">Divorciado(a)</option>
                <option value="viuvo">Viúvo(a)</option>
              </select>
            </div>
          </div>

          <div class="reg-field-grid-2">
            <div class="form-group">
              <label>CPF <span class="reg-required">*</span></label>
              <input
                :value="formatCpfDisplay(patient.cpf)"
                type="text"
                class="form-input"
                placeholder="000.000.000-00"
                @input="handleCpfInput"
              />
            </div>
            <div class="form-group">
              <label>RG / Órgão Emissor</label>
              <input
                :value="formatRgDisplay(patient.rg)"
                type="text"
                class="form-input"
                placeholder="00.000.000-0"
                @input="handleRgInput"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 2: CONTATO ── -->
      <div class="reg-section">
        <button class="reg-section-toggle" @click="toggleRegSection('contact')">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-green">
              <i class="i-lucide-phone w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Contato e Comunicação</span>
              <span class="reg-section-subtitle"
                >Telefone, e-mail, preferências</span
              >
            </div>
          </div>
          <i
            class="i-lucide-chevron-down w-4 h-4 reg-chevron"
            :class="{ 'reg-chevron-open': regSections.contact }"
          />
        </button>

        <div v-if="regSections.contact" class="reg-section-body">
          <div class="reg-field-grid-2">
            <div class="form-group reg-field-relative">
              <label>
                Telefone Principal
                <span class="reg-badge-wpp"
                  ><i class="i-lucide-message-circle w-3 h-3" /> WhatsApp</span
                >
                <span class="reg-required">*</span>
              </label>
              <input
                type="text"
                class="form-input"
                placeholder="(00) 00000-0000"
                :value="patient.phone"
                autocomplete="off"
                @focus="onPhoneInputFocus"
                @blur="onPhoneInputBlur"
                @input="handlePhoneInput"
              />

              <!-- Dropdown de contatos semelhante ao Modal de Novo Paciente -->
              <div
                v-if="showDropdown && (isSearching || searchResults.length > 0)"
                class="reg-contact-dropdown"
              >
                <div v-if="isSearching" class="reg-dropdown-loading">
                  Buscando...
                </div>
                <ul v-else class="reg-dropdown-list">
                  <li
                    v-for="contact in searchResults"
                    :key="contact.id"
                    class="reg-dropdown-item"
                    @mousedown.prevent="selectContact(contact)"
                  >
                    <span
                      v-if="contact.avatar_url"
                      class="reg-item-avatar reg-item-avatar--img"
                    >
                      <img :src="contact.avatar_url" :alt="contact.name" />
                    </span>
                    <span
                      v-else
                      class="reg-item-avatar"
                      :style="{ background: getContactColor(contact.name) }"
                    >
                      {{ getInitial(contact.name) }}
                    </span>
                    <div class="reg-item-info">
                      <span class="reg-item-name">{{
                        contact.name || 'Sem nome'
                      }}</span>
                      <span class="reg-item-phone">{{
                        contact.phone_number
                      }}</span>
                    </div>
                  </li>
                </ul>
              </div>
            </div>
            <div class="form-group">
              <label>Telefone Alternativo</label>
              <input
                :value="formatPhoneDisplay(patient.emergency_contact?.phone)"
                type="text"
                class="form-input"
                placeholder="(11) 00000-0000"
                @input="handleAlternativePhoneInput"
              />
            </div>
          </div>

          <div class="form-group">
            <label>E-mail</label>
            <input
              v-model="patient.email"
              type="email"
              class="form-input"
              placeholder="paciente@email.com"
            />
          </div>

          <div class="reg-divider" />

          <p class="reg-subsection-label">Preferências de contato</p>
          <div class="reg-opt-in-grid">
            <label class="reg-opt-in-card">
              <div class="reg-opt-in-info">
                <i class="i-lucide-message-circle w-4 h-4 text-green-400" />
                <div>
                  <p class="text-sm font-medium text-slate-200">WhatsApp</p>
                  <p class="text-xs text-slate-500">Lembretes e confirmações</p>
                </div>
              </div>
              <div
                class="reg-toggle"
                :class="{
                  'reg-toggle-on': patient.communication_opt_ins.whatsapp,
                }"
                @click="
                  patient.communication_opt_ins.whatsapp =
                    !patient.communication_opt_ins.whatsapp
                "
              >
                <div class="reg-toggle-thumb" />
              </div>
            </label>
            <label class="reg-opt-in-card">
              <div class="reg-opt-in-info">
                <i class="i-lucide-mail w-4 h-4 text-blue-400" />
                <div>
                  <p class="text-sm font-medium text-slate-200">E-mail</p>
                  <p class="text-xs text-slate-500">
                    Comprovantes e comunicados
                  </p>
                </div>
              </div>
              <div
                class="reg-toggle"
                :class="{
                  'reg-toggle-on': patient.communication_opt_ins.email,
                }"
                @click="
                  patient.communication_opt_ins.email =
                    !patient.communication_opt_ins.email
                "
              >
                <div class="reg-toggle-thumb" />
              </div>
            </label>
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 3: ENDEREÇO ── -->
      <div class="reg-section">
        <button class="reg-section-toggle" @click="toggleRegSection('address')">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-amber">
              <i class="i-lucide-map-pin w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Endereço</span>
              <span class="reg-section-subtitle">CEP, rua, cidade, estado</span>
            </div>
          </div>
          <i
            class="i-lucide-chevron-down w-4 h-4 reg-chevron"
            :class="{ 'reg-chevron-open': regSections.address }"
          />
        </button>

        <div v-if="regSections.address" class="reg-section-body">
          <div class="reg-field-grid-cep">
            <div class="form-group">
              <label>CEP</label>
              <div class="input-with-action">
                <input
                  v-model="patient.address.zip_code"
                  type="text"
                  class="form-input"
                  placeholder="00000-000"
                />
                <button class="btn-icon-inside" @click.prevent="searchCep">
                  <i class="i-lucide-search w-4 h-4" />
                </button>
              </div>
            </div>
            <div class="form-group">
              <label>Rua / Avenida</label>
              <input
                v-model="patient.address.street"
                type="text"
                class="form-input"
              />
            </div>
          </div>

          <div class="reg-field-grid-3">
            <div class="form-group">
              <label>Número</label>
              <input
                v-model="patient.address.number"
                type="text"
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label>Complemento</label>
              <input
                v-model="patient.address.complement"
                type="text"
                class="form-input"
                placeholder="Apto, bloco..."
              />
            </div>
            <div class="form-group">
              <label>Bairro</label>
              <input
                v-model="patient.address.neighborhood"
                type="text"
                class="form-input"
              />
            </div>
          </div>

          <div class="reg-field-grid-2">
            <div class="form-group">
              <label>Cidade</label>
              <input
                v-model="patient.address.city"
                type="text"
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label>Estado (UF)</label>
              <select v-model="patient.address.state" class="form-input">
                <option value="AC">AC</option>
                <option value="AL">AL</option>
                <option value="AM">AM</option>
                <option value="AP">AP</option>
                <option value="BA">BA</option>
                <option value="CE">CE</option>
                <option value="DF">DF</option>
                <option value="ES">ES</option>
                <option value="GO">GO</option>
                <option value="MA">MA</option>
                <option value="MG">MG</option>
                <option value="MS">MS</option>
                <option value="MT">MT</option>
                <option value="PA">PA</option>
                <option value="PB">PB</option>
                <option value="PE">PE</option>
                <option value="PI">PI</option>
                <option value="PR">PR</option>
                <option value="RJ">RJ</option>
                <option value="RN">RN</option>
                <option value="RO">RO</option>
                <option value="RR">RR</option>
                <option value="RS">RS</option>
                <option value="SC">SC</option>
                <option value="SE">SE</option>
                <option value="SP">SP</option>
                <option value="TO">TO</option>
              </select>
            </div>
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 4: ADMINISTRATIVO ── -->
      <div class="reg-section">
        <button class="reg-section-toggle" @click="toggleRegSection('admin')">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-purple">
              <i class="i-lucide-briefcase w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Administrativo e Convênio</span>
              <span class="reg-section-subtitle"
                >Plano de saúde, emergência, LGPD</span
              >
            </div>
          </div>
          <i
            class="i-lucide-chevron-down w-4 h-4 reg-chevron"
            :class="{ 'reg-chevron-open': regSections.admin }"
          />
        </button>

        <div v-if="regSections.admin" class="reg-section-body">
          <p class="reg-subsection-label">Plano de Saúde / Convênio</p>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label>Convênio</label>
              <select v-model="patient.insurance.name" class="form-input">
                <option value="Particular">Particular</option>
                <option value="Bradesco Saúde">Bradesco Saúde</option>
                <option value="SulAmérica">SulAmérica</option>
                <option value="Amil">Amil</option>
                <option value="Unimed">Unimed</option>
                <option value="Porto Seguro">Porto Seguro</option>
              </select>
            </div>
            <div class="form-group">
              <label>Nº da Carteirinha</label>
              <input
                v-model="patient.insurance.number"
                type="text"
                class="form-input"
                placeholder="000.000.000"
              />
            </div>
          </div>
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label>Plano</label>
              <input
                v-model="patient.insurance.plan"
                type="text"
                class="form-input"
                placeholder="Ex: Executivo Plus"
              />
            </div>
            <div class="form-group">
              <label>Validade da Carteirinha</label>
              <input
                v-model="patient.insurance.valid_until"
                type="date"
                class="form-input"
                min="1900-01-01"
                max="2100-12-31"
              />
            </div>
          </div>

          <div class="reg-divider" />

          <p class="reg-subsection-label">Contato de Emergência</p>
          <div class="reg-field-grid-3">
            <div class="form-group">
              <label>Nome</label>
              <input
                v-model="patient.emergency_contact.name"
                type="text"
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label>Telefone</label>
              <input
                v-model="patient.emergency_contact.phone"
                type="text"
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label>Grau de Parentesco</label>
              <input
                v-model="patient.emergency_contact.relationship"
                type="text"
                class="form-input"
                placeholder="Ex: Cônjuge"
              />
            </div>
          </div>

          <div class="reg-divider" />

          <p class="reg-subsection-label">LGPD e Consentimentos</p>
          <div class="reg-opt-in-grid">
            <label class="reg-opt-in-card">
              <div class="reg-opt-in-info">
                <i class="i-lucide-shield-check w-4 h-4 text-blue-400" />
                <div>
                  <p class="text-sm font-medium text-slate-200">Termo LGPD</p>
                  <p class="text-xs text-slate-500">
                    Armazenamento de dados médicos
                  </p>
                </div>
              </div>
              <div
                class="reg-toggle"
                :class="{
                  'reg-toggle-on': patient.lgpd_consent.accepted,
                }"
                @click="
                  patient.lgpd_consent.accepted = !patient.lgpd_consent.accepted
                "
              >
                <div class="reg-toggle-thumb" />
              </div>
            </label>
            <label class="reg-opt-in-card">
              <div class="reg-opt-in-info">
                <i class="i-lucide-image w-4 h-4 text-purple-400" />
                <div>
                  <p class="text-sm font-medium text-slate-200">
                    Uso de Imagem
                  </p>
                  <p class="text-xs text-slate-500">
                    Marketing e redes sociais
                  </p>
                </div>
              </div>
              <div
                class="reg-toggle"
                :class="{
                  'reg-toggle-on': patient.lgpd_consent.image_use_accepted,
                }"
                @click="
                  patient.lgpd_consent.image_use_accepted =
                    !patient.lgpd_consent.image_use_accepted
                "
              >
                <div class="reg-toggle-thumb" />
              </div>
            </label>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.reg-field-relative {
  position: relative;
}

.reg-contact-dropdown {
  position: absolute;
  top: calc(100% + 2px);
  left: 0;
  right: 0;
  z-index: 50;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.1);
  overflow: hidden;
  max-height: 190px;
  overflow-y: auto;
}

.reg-dropdown-loading {
  padding: 10px 14px;
  font-size: 13px;
  color: rgb(var(--slate-9));
}
.reg-dropdown-list {
  list-style: none;
  margin: 0;
  padding: 4px;
}
.reg-dropdown-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.1s;
}
.reg-dropdown-item:hover {
  background: rgb(var(--slate-3));
}
.reg-item-avatar {
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
.reg-item-avatar--img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.reg-item-info {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
}
.reg-item-name {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.reg-item-phone {
  font-size: 11px;
  color: rgb(var(--slate-9));
}
</style>
