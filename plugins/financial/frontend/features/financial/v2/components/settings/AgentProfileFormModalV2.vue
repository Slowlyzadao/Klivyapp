<script setup>
/**
 * Modal de cadastrar/editar perfil financeiro de profissional.
 *
 * 3 modos:
 *   1. Adicionar perfil pra User existente (sem profile ainda) → dropdown
 *   2. Criar User novo + profile no mesmo fluxo → form de novo usuário
 *   3. Editar profile existente → User vem fixo via prop `user`
 *
 * Backend dual-call quando criar novo:
 *   POST /api/v1/accounts/:id/agents       (AgentBuilder core — cria User)
 *   PUT  /financial/v2/agent_profiles/:id  (upsert profile financeiro)
 *
 * Props:
 *   - show: Boolean
 *   - user: Object | null — User core (modo 3) ou null (modos 1/2)
 *   - existingProfile: Object | null — profile atual ou null
 *   - existingUsers: Array — lista de Users da conta (pra dropdown do modo 1)
 *   - usersWithProfile: Set<Number> — IDs de users que já têm profile (excluir do dropdown)
 *
 * Eventos:
 *   - close
 *   - confirm
 *   - deactivate: userId
 */
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import { maskDocument } from '@plugins/beclinic_core/frontend/utils/documentMasks';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import FinancialV2 from '../../api/financialV2';
import AgentsAPI from 'dashboard/api/agents';
import ConfirmDangerModalV2 from '../ConfirmDangerModalV2.vue';

const { t } = useI18n();

const props = defineProps({
  show: { type: Boolean, default: false },
  user: { type: Object, default: null },
  existingProfile: { type: Object, default: null },
  existingUsers: { type: Array, default: () => [] },
  usersWithProfile: { type: Set, default: () => new Set() },
});

const emit = defineEmits(['close', 'confirm', 'deactivate']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Estados do modal:
// - 'pick'    : escolher se vai linkar User existente ou criar novo (modos 1/2)
// - 'newuser' : form de novo User (modo 2)
// - 'profile' : form de perfil financeiro (modos 1/2/3 após selecionar User)
const mode = ref('profile');

const selectedUserId = ref(null);
const newUserForm = ref({ name: '', email: '', role: 'agent' });
const submitting = ref(false);

// Form do profile financeiro
const form = ref({
  cpf: '',
  agent_category: 'profissional',
  bond_type: 'PJ',
  entry_date: new Date().toISOString().slice(0, 10),
  commissionable: true,
  cro: '',
  specialties: [],
  bank_name: '',
  bank_agency: '',
  bank_account_number: '',
  pix_key: '',
  status: 'active',
  notes: '',
});

const isEdit = computed(() => !!props.existingProfile);
const currentUser = ref(null); // User atual (vem de prop ou foi criado/escolhido)

// ── Categorias e vínculos (canon mapa-financeiro) ────────────────────
const CATEGORY_OPTIONS = [
  { value: 'profissional', label: 'Profissional (clínico)' },
  { value: 'operacional',  label: 'Operacional (recepção, auxiliar)' },
  { value: 'comercial',    label: 'Comercial (vendas, SDR)' },
  { value: 'administrador', label: 'Administrador (não-comissionável)' },
];

const BOND_OPTIONS = [
  { value: 'PJ',    label: 'PJ' },
  { value: 'PF',    label: 'PF (Pessoa Física)' },
  { value: 'CLT',   label: 'CLT' },
  { value: 'Socio', label: 'Sócio' },
];

const STATUS_OPTIONS = [
  { value: 'active',   label: 'Ativo' },
  { value: 'inactive', label: 'Inativo' },
];

// Dropdown de Users existentes (excluindo os que já têm profile)
// Espelha `getAgentRoleName` de /settings/agents — mesmo label do badge.
function getAgentRoleName(user) {
  if (user.beclinic_super_admin) return 'Super Admin';
  if (user.role === 'administrator') {
    return t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR');
  }
  if (user.klivy_role?.name) return user.klivy_role.name;
  if (!user.custom_role_id && user.role) {
    return t(`AGENT_MGMT.AGENT_TYPES.${user.role.toUpperCase()}`);
  }
  return '';
}

// Espelha `hasRoleBadge` — administrador não exibe badge (já tem destaque),
// mas vamos exibir SEMPRE no contexto financeiro pra dar contexto rápido.
function getRoleLabel(user) {
  return getAgentRoleName(user) || (user.role === 'agent' ? 'Agente' : '—');
}

const availableUsers = computed(() => {
  // Carrega `user` inteiro como `meta` da option pra o slot custom acessar
  // avatar + role badge.
  return props.existingUsers
    .filter(u => !props.usersWithProfile.has(u.id))
    .map(u => ({ value: u.id, label: u.name, user: u }));
});

// CRO obrigatório se profissional (espelha check constraint do banco)
const requiresCRO = computed(() => form.value.agent_category === 'profissional');

// Documento adapta ao vínculo: PJ (Pessoa Jurídica) → CNPJ; demais (PF/CLT/Sócio,
// pessoa física) → CPF. A mesma coluna `cpf` guarda os dois — o backend só
// normaliza pra dígitos + criptografa (sem validação de formato), então CNPJ
// (14 dígitos) cabe sem migração. Rename futuro p/ `tax_id` seria mais limpo.
const isPJ = computed(() => form.value.bond_type === 'PJ');
const documentLabel = computed(() => (isPJ.value ? 'CNPJ' : 'CPF'));
const documentPlaceholder = computed(() => (isPJ.value ? '00.000.000/0000-00' : '000.000.000-00'));

// Máscara CPF/CNPJ ao digitar (util compartilhado beclinic_core). Por isso o
// input usa :value + @input em vez de v-model. Backend normaliza pra dígitos,
// então a máscara é só de exibição.
function onDocumentInput(e) {
  const masked = maskDocument(e.target.value, { pj: isPJ.value });
  form.value.cpf = masked;
  // Força o DOM a refletir a máscara MESMO quando o valor do model não muda —
  // ex: dígito além do limite (12º no CPF / 15º no CNPJ) ou paste com lixo.
  // Sem isto o Vue não re-renderiza o :value e o campo exibe dígitos a mais.
  // Mesmo padrão do handleCpfInput do cadastro de paciente.
  e.target.value = masked;
}

// Trocar o vínculo cruzando a fronteira CPF↔CNPJ (PF/CLT/Sócio ↔ PJ) zera o
// documento — CPF e CNPJ são incompatíveis (11 vs 14 dígitos). Trocas dentro do
// mesmo tipo (ex: PF→CLT) preservam o que já foi digitado. Feito no @update do
// select (só dispara em ação do usuário), então NÃO zera no load/edição.
function onBondTypeChange(newBond) {
  const crossesDocBoundary = isPJ.value !== (newBond === 'PJ');
  form.value.bond_type = newBond;
  if (crossesDocBoundary) form.value.cpf = '';
}

// Administrador NUNCA é comissionável
watch(() => form.value.agent_category, (cat) => {
  if (cat === 'administrador') form.value.commissionable = false;
});

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!currentUser.value) return false;
  if (!form.value.agent_category) return false;
  if (!form.value.bond_type) return false;
  if (!form.value.entry_date) return false;
  if (requiresCRO.value && !form.value.cro?.trim()) return false;
  return true;
});

const titleText = computed(() => {
  if (mode.value === 'pick') return 'Adicionar profissional';
  if (mode.value === 'newuser') return 'Criar novo usuário';
  if (isEdit.value) return `Editar profissional — ${currentUser.value?.name}`;
  return `Configurar perfil financeiro — ${currentUser.value?.name}`;
});

// ── Inicialização ────────────────────────────────────────────────────
watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;

    if (props.user) {
      // Modos 1 ou 3 — User já vem da row clicada
      currentUser.value = props.user;
      mode.value = 'profile';
      if (props.existingProfile) {
        // Edit
        form.value = {
          cpf: maskDocument(props.existingProfile.cpf || '', { pj: props.existingProfile.bond_type === 'PJ' }),
          agent_category: props.existingProfile.agent_category,
          bond_type: props.existingProfile.bond_type,
          entry_date: props.existingProfile.entry_date,
          commissionable: props.existingProfile.commissionable,
          cro: props.existingProfile.cro || '',
          specialties: props.existingProfile.specialties || [],
          bank_name: props.existingProfile.bank_name || '',
          bank_agency: props.existingProfile.bank_agency || '',
          bank_account_number: props.existingProfile.bank_account_number || '',
          pix_key: props.existingProfile.pix_key || '',
          status: props.existingProfile.status,
          notes: props.existingProfile.notes || '',
        };
      } else {
        resetForm();
      }
    } else {
      // Botão "+ Adicionar" do header — começa no picker
      currentUser.value = null;
      mode.value = 'pick';
      selectedUserId.value = null;
      newUserForm.value = { name: '', email: '', role: 'agent' };
      resetForm();
    }
  },
  { immediate: true },
);

function resetForm() {
  form.value = {
    cpf: '',
    agent_category: 'profissional',
    bond_type: 'PJ',
    entry_date: new Date().toISOString().slice(0, 10),
    commissionable: true,
    cro: '',
    specialties: [],
    bank_name: '',
    bank_agency: '',
    bank_account_number: '',
    pix_key: '',
    status: 'active',
    notes: '',
  };
}

// ── Fluxo do picker ──────────────────────────────────────────────────
function pickExistingUser() {
  if (!selectedUserId.value) {
    notifyError('Escolha um usuário antes de continuar.');
    return;
  }
  const found = props.existingUsers.find(u => u.id === selectedUserId.value);
  if (!found) {
    notifyError('Usuário não encontrado.');
    return;
  }
  currentUser.value = found;
  mode.value = 'profile';
}

function startNewUser() {
  mode.value = 'newuser';
}

function backToPicker() {
  mode.value = 'pick';
}

// ── Criar User novo via AgentBuilder core ─────────────────────────────
async function createUserAndProceed() {
  const { name, email, role } = newUserForm.value;
  if (!name?.trim() || !email?.trim()) {
    notifyError('Preencha nome e email.');
    return;
  }
  submitting.value = true;
  try {
    const res = await AgentsAPI.create({
      name: name.trim(),
      email: email.trim(),
      role: role || 'agent',
    });
    // AgentBuilder retorna o User criado — pode vir em diferentes formatos
    // dependendo da versão. Tenta extrair `data` ou diretamente.
    const created = res?.data?.data || res?.data || {};
    currentUser.value = {
      id: created.id || created.user_id,
      name: created.name || name.trim(),
      email: created.email || email.trim(),
    };
    notifySuccess(`Usuário criado. Convite enviado para ${email}.`);
    mode.value = 'profile';
  } catch (err) {
    const msg = err?.response?.data?.message
      || err?.response?.data?.errors?.join('; ')
      || 'Erro ao criar usuário.';
    notifyError(msg);
  } finally {
    submitting.value = false;
  }
}

// ── Salvar profile financeiro ─────────────────────────────────────────
async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      agent_profile: {
        cpf: form.value.cpf || null,
        agent_category: form.value.agent_category,
        bond_type: form.value.bond_type,
        entry_date: form.value.entry_date,
        commissionable: !!form.value.commissionable,
        cro: requiresCRO.value ? form.value.cro : null,
        specialties: form.value.specialties || [],
        bank_name: form.value.bank_name || null,
        bank_agency: form.value.bank_agency || null,
        bank_account_number: form.value.bank_account_number || null,
        pix_key: form.value.pix_key || null,
        status: form.value.status,
        notes: form.value.notes || null,
      },
    };
    await FinancialV2.agentProfiles.upsert(currentUser.value.id, payload);
    notifySuccess(isEdit.value ? 'Perfil atualizado.' : 'Perfil financeiro configurado.');
    emit('confirm');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao salvar perfil');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

// Substitui qualquer confirm() nativo por modal padronizado.
const deactivateConfirmOpen = ref(false);

function onClickDeactivate() {
  if (submitting.value || !isEdit.value) return;
  deactivateConfirmOpen.value = true;
}

function confirmDeactivate() {
  deactivateConfirmOpen.value = false;
  emit('deactivate', currentUser.value.id);
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="agm-v2__backdrop">
      <div class="agm-v2__modal" role="dialog" aria-modal="true">
        <header class="agm-v2__header">
          <div class="agm-v2__header-text">
            <h2 class="agm-v2__title">
              <i class="i-lucide-user-cog agm-v2__title-icon" />
              {{ titleText }}
            </h2>
            <p v-if="currentUser && mode === 'profile'" class="agm-v2__subtitle">
              {{ currentUser.email }}
            </p>
          </div>
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :disabled="submitting"
            @click="close"
          />
        </header>

        <!-- ── Modo PICK: escolher User existente OU criar novo ── -->
        <div v-if="mode === 'pick'" class="agm-v2__body">
          <div class="agm-v2__pick-box">
            <h3 class="agm-v2__pick-title">Vincular usuário existente</h3>
            <p class="agm-v2__pick-hint">
              Escolha um usuário já cadastrado em <strong>Configurações &gt; Agentes</strong>.
            </p>
            <FormSelect
              v-model="selectedUserId"
              :options="availableUsers"
              placeholder="Selecione um usuário..."
              auto-searchable
            >
              <template #option="{ option }">
                <span class="agm-v2__user-row">
                  <Avatar
                    :src="option.user?.avatar_url || ''"
                    :name="option.user?.name"
                    :size="24"
                    rounded-full
                  />
                  <span class="agm-v2__user-name">{{ option.user?.name }}</span>
                  <span class="agm-v2__user-role">{{ getRoleLabel(option.user) }}</span>
                </span>
              </template>
              <template #selected="{ option }">
                <span v-if="option" class="agm-v2__user-row agm-v2__user-row--trigger">
                  <Avatar
                    :src="option.user?.avatar_url || ''"
                    :name="option.user?.name"
                    :size="22"
                    rounded-full
                  />
                  <span class="agm-v2__user-name">{{ option.user?.name }}</span>
                  <span class="agm-v2__user-role">{{ getRoleLabel(option.user) }}</span>
                </span>
              </template>
            </FormSelect>
            <p v-if="availableUsers.length === 0" class="agm-v2__pick-empty">
              Todos os usuários da conta já têm perfil financeiro cadastrado.
            </p>
            <BeclinicButton
              variant="solid"
              color="blue"
              icon="i-lucide-arrow-right"
              label="Continuar"
              :disabled="!selectedUserId"
              @click="pickExistingUser"
            />
          </div>

          <div class="agm-v2__pick-divider">
            <span>OU</span>
          </div>

          <div class="agm-v2__pick-box">
            <h3 class="agm-v2__pick-title">Criar usuário novo</h3>
            <p class="agm-v2__pick-hint">
              Cria um usuário em <strong>Agentes</strong> + perfil financeiro em sequência.
              Convite por email será enviado.
            </p>
            <BeclinicButton
              variant="ghost"
              color="slate"
              icon="i-lucide-user-plus"
              label="Criar novo usuário"
              @click="startNewUser"
            />
          </div>
        </div>

        <!-- ── Modo NEW USER: form de novo agente ── -->
        <div v-else-if="mode === 'newuser'" class="agm-v2__body">
          <label class="agm-v2__field">
            <span class="agm-v2__field-label">Nome <span class="agm-v2__required">*</span></span>
            <input
              v-model="newUserForm.name"
              type="text"
              class="finv2-input"
              placeholder="Nome completo"
              maxlength="80"
            />
          </label>
          <label class="agm-v2__field">
            <span class="agm-v2__field-label">Email <span class="agm-v2__required">*</span></span>
            <input
              v-model="newUserForm.email"
              type="email"
              class="finv2-input"
              placeholder="email@exemplo.com"
            />
            <span class="agm-v2__field-hint-mini">
              Receberá convite para definir senha de acesso.
            </span>
          </label>
          <label class="agm-v2__field">
            <span class="agm-v2__field-label">Papel no sistema</span>
            <FormSelect
              v-model="newUserForm.role"
              :options="[
                { value: 'agent', label: 'Agente (acesso padrão)' },
                { value: 'administrator', label: 'Administrador' },
              ]"
            />
            <span class="agm-v2__field-hint-mini">
              Definição de RBAC fina (Klivy Role) pode ser feita depois em Agentes.
            </span>
          </label>

          <div class="agm-v2__back-bar">
            <BeclinicButton
              variant="ghost"
              color="slate"
              icon="i-lucide-arrow-left"
              label="Voltar"
              :disabled="submitting"
              @click="backToPicker"
            />
            <BeclinicButton
              variant="solid"
              color="blue"
              icon="i-lucide-check"
              label="Criar usuário e continuar"
              :is-loading="submitting"
              :disabled="submitting || !newUserForm.name || !newUserForm.email"
              @click="createUserAndProceed"
            />
          </div>
        </div>

        <!-- ── Modo PROFILE: form de perfil financeiro ── -->
        <div v-else class="agm-v2__body">
          <div class="agm-v2__row">
            <label class="agm-v2__field">
              <span class="agm-v2__field-label">
                Categoria <span class="agm-v2__required">*</span>
              </span>
              <FormSelect
                v-model="form.agent_category"
                :options="CATEGORY_OPTIONS"
              />
            </label>

            <label class="agm-v2__field">
              <span class="agm-v2__field-label">
                Vínculo <span class="agm-v2__required">*</span>
              </span>
              <FormSelect
                :model-value="form.bond_type"
                :options="BOND_OPTIONS"
                @update:model-value="onBondTypeChange"
              />
            </label>
          </div>

          <div class="agm-v2__row">
            <label class="agm-v2__field">
              <span class="agm-v2__field-label">{{ documentLabel }}</span>
              <input
                :value="form.cpf"
                type="text"
                class="finv2-input"
                :placeholder="documentPlaceholder"
                maxlength="20"
                @input="onDocumentInput"
              />
              <span class="agm-v2__field-hint-mini">
                Armazenado criptografado (LGPD).
              </span>
            </label>

            <label v-if="requiresCRO" class="agm-v2__field">
              <span class="agm-v2__field-label">
                CRO <span class="agm-v2__required">*</span>
              </span>
              <input
                v-model="form.cro"
                type="text"
                class="finv2-input"
                placeholder="Ex.: CRO-SP 12345"
                maxlength="40"
              />
            </label>
          </div>

          <div class="agm-v2__row">
            <label class="agm-v2__field">
              <span class="agm-v2__field-label">
                Data de entrada <span class="agm-v2__required">*</span>
              </span>
              <DatePickerBR
                v-model="form.entry_date"
                placeholder="DD/MM/AAAA"
                :clearable="false"
              />
            </label>

            <label class="agm-v2__field">
              <span class="agm-v2__field-label">Status</span>
              <FormSelect
                v-model="form.status"
                :options="STATUS_OPTIONS"
              />
            </label>
          </div>

          <div class="agm-v2__checkbox-wrap">
            <Checkbox
              v-model="form.commissionable"
              :disabled="form.agent_category === 'administrador'"
            >
              <span>
                Comissionado
                <span v-if="form.agent_category === 'administrador'" class="agm-v2__checkbox-disabled-hint">
                  (administrador nunca é comissionado)
                </span>
              </span>
            </Checkbox>
          </div>

          <!-- Dados bancários (collapsible) -->
          <details class="agm-v2__details">
            <summary>Dados bancários (pagamento de comissão)</summary>
            <div class="agm-v2__details-content">
              <div class="agm-v2__row">
                <label class="agm-v2__field">
                  <span class="agm-v2__field-label">Banco</span>
                  <input v-model="form.bank_name" type="text" class="finv2-input" maxlength="120" placeholder="Ex.: Itaú" />
                </label>
                <label class="agm-v2__field">
                  <span class="agm-v2__field-label">Agência</span>
                  <input v-model="form.bank_agency" type="text" class="finv2-input" maxlength="20" placeholder="Ex.: 0001" />
                </label>
              </div>
              <div class="agm-v2__row">
                <label class="agm-v2__field">
                  <span class="agm-v2__field-label">Conta</span>
                  <input v-model="form.bank_account_number" type="text" class="finv2-input" maxlength="40" placeholder="Ex.: 12345-6" />
                </label>
                <label class="agm-v2__field">
                  <span class="agm-v2__field-label">Chave PIX</span>
                  <input v-model="form.pix_key" type="text" class="finv2-input" maxlength="120" placeholder="CPF/email/telefone/chave aleatória" />
                </label>
              </div>
            </div>
          </details>

          <label class="agm-v2__field">
            <span class="agm-v2__field-label">Observações</span>
            <textarea
              v-model="form.notes"
              class="finv2-input"
              rows="2"
              placeholder="Notas internas..."
            />
          </label>
        </div>

        <!-- Footer -->
        <footer v-if="mode === 'profile'" class="agm-v2__footer">
          <BeclinicButton
            v-if="isEdit"
            variant="ghost"
            color="ruby"
            icon="i-lucide-archive"
            label="Inativar perfil"
            :disabled="submitting"
            @click="onClickDeactivate"
          />
          <div class="agm-v2__footer-actions">
            <BeclinicButton
              variant="ghost"
              color="slate"
              label="Cancelar"
              :disabled="submitting"
              @click="close"
            />
            <BeclinicButton
              variant="solid"
              color="blue"
              icon="i-lucide-check"
              :label="isEdit ? 'Salvar alterações' : 'Salvar perfil'"
              :is-loading="submitting"
              :disabled="!validForSubmit"
              @click="submit"
            />
          </div>
        </footer>
      </div>
    </div>
  </Teleport>

  <ConfirmDangerModalV2
    v-if="deactivateConfirmOpen"
    :show="deactivateConfirmOpen"
    title="Inativar perfil financeiro?"
    confirm-label="Sim, inativar"
    tone="warn"
    @close="deactivateConfirmOpen = false"
    @confirm="confirmDeactivate"
  >
    Inativar perfil financeiro de <strong>{{ currentUser?.name }}</strong>.
    <br>
    O usuário core <strong>permanece intacto</strong> em <em>Configurações &gt; Agentes</em>,
    mas comissões e folha não estarão mais disponíveis.
  </ConfirmDangerModalV2>
</template>

<style scoped lang="scss">
.agm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .agm-v2__backdrop { align-items: center; padding: 16px; }
}

.agm-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .agm-v2__modal {
    width: min(620px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.agm-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.agm-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.agm-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--emerald-9)); }
.agm-v2__subtitle { margin: 6px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }

.agm-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

/* ── Picker ───────────────────────────────────────────────── */
.agm-v2__pick-box {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 16px;
  display: flex; flex-direction: column; gap: 10px;
}
.agm-v2__pick-title {
  margin: 0; font-size: 14px; font-weight: 600;
  color: rgb(var(--slate-12));
}
.agm-v2__pick-hint {
  margin: 0; font-size: 12px;
  color: rgb(var(--slate-10));
  line-height: 1.4;
}
.agm-v2__pick-empty {
  margin: 0; font-size: 12px;
  font-style: italic;
  color: rgb(var(--amber-10));
}

/* ── User row no dropdown (custom slot do FormSelect) ───────── */
.agm-v2__user-row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1;
  min-width: 0;

  &--trigger {
    /* No trigger (botão fechado), Avatar menor e gap menor */
    gap: 8px;
  }
}

.agm-v2__user-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
  color: rgb(var(--slate-12));
  font-weight: 500;
}

.agm-v2__user-role {
  flex-shrink: 0;
  padding: 2px 8px;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  background: rgba(59, 130, 246, 0.1);
  color: rgb(var(--blue-11));
}
.agm-v2__pick-divider {
  display: flex; align-items: center; gap: 10px;
  color: rgb(var(--slate-9));
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.1em;
  &::before, &::after {
    content: ''; flex: 1;
    border-top: 1px solid rgb(var(--slate-4));
  }
}

/* ── Form ──────────────────────────────────────────────────── */
.agm-v2__row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }
}

.agm-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.agm-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.agm-v2__required { color: rgb(var(--ruby-9)); }
.agm-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

.agm-v2__checkbox-wrap {
  display: flex;
  align-items: center;
  padding: 4px 0;
}
.agm-v2__checkbox-disabled-hint {
  color: rgb(var(--slate-9));
  font-size: 11px;
  font-style: italic;
  margin-left: 4px;
}

.agm-v2__details {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  summary {
    padding: 10px 14px;
    cursor: pointer;
    font-size: 12px;
    color: rgb(var(--slate-11));
    user-select: none;
    &:hover { color: rgb(var(--slate-12)); }
  }
}
.agm-v2__details-content {
  padding: 0 14px 14px;
  display: flex; flex-direction: column; gap: 10px;
}

.agm-v2__back-bar {
  display: flex; justify-content: space-between; gap: 8px;
  margin-top: 8px;
  padding-top: 14px;
  border-top: 1px solid rgb(var(--slate-4));
}

.agm-v2__footer {
  display: flex; justify-content: space-between; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
  @media (max-width: 480px) {
    flex-direction: column-reverse;
    .agm-v2__footer-actions {
      flex-direction: column-reverse;
      width: 100%;
      > * { width: 100%; }
    }
  }
}
.agm-v2__footer-actions {
  display: flex; gap: 8px; margin-left: auto;
}
</style>
