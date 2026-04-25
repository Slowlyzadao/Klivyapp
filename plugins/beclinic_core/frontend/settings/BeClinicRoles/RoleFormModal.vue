<script setup>
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import BeClinicRolesAPI from '@plugins/beclinic_core/frontend/api/beclinicRoles';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  mode: { type: String, default: 'add' }, // 'add' | 'edit'
  role: { type: Object, default: null },
});

const emit = defineEmits(['close', 'saved']);

// ─── Form state ───────────────────────────────────────────────────────────────
const isSaving = ref(false);
const activeTab = ref('preset'); // 'preset' | 'custom'

const PRESET_OPTIONS = [
  {
    key: 'recepcionista',
    label: 'Recepcionista',
    icon: '👩‍💼',
    description: 'Gerencia agenda, atende pacientes, sem acesso clínico',
    beclinic_role: 'gerente',
  },
  {
    key: 'especialista',
    label: 'Especialista / Dentista',
    icon: '🦷',
    description: 'Acesso clínico completo, visualiza apenas seus pacientes',
    beclinic_role: 'especialista',
  },
  {
    key: 'gerente',
    label: 'Gerente',
    icon: '🏢',
    description:
      'Acesso quase completo, inclui relatórios e gestão de usuários',
    beclinic_role: 'gerente',
  },
  {
    key: 'sdr',
    label: 'SDR / Comercial',
    icon: '📣',
    description: 'Foco em orçamentos e chat, sem acesso clínico',
    beclinic_role: 'especialista',
  },
];

const selectedPreset = ref(null);
const formName = ref('');
const formBeclinicRole = ref('gerente');

// Permissions form — initially all false
const defaultPermissions = () => ({
  patients: {
    scope: 'all',
    view: false,
    create: false,
    edit: false,
    delete: false,
    view_clinical_notes: false,
    create_clinical_notes: false,
    sign_clinical_notes: false,
    delete_clinical_notes: false,
    view_treatment_plans: false,
    manage_treatment_plans: false,
    view_consents: false,
    manage_consents: false,
    view_documents: false,
    manage_documents: false,
    view_exams: false,
    manage_exams: false,
    view_audit: false,
    view_timeline: false,
  },
  agenda: {
    scope: 'all',
    view: false,
    create_event: false,
    edit_event: false,
    cancel_event: false,
    drag_and_drop: false,
    manage_blocks: false,
    view_notifications: false,
    manage_notifications: false,
  },
  financial: {
    view_transactions: false,
    create_transaction: false,
    delete_transaction: false,
    view_estimates: false,
    create_estimate: false,
    edit_estimate: false,
    approve_estimate: false,
    delete_estimate: false,
    view_cashflow: false,
    export_cashflow: false,
  },
  chat: {
    view_all: false,
    view_unassigned: false,
    reply: false,
    assign_conversation: false,
    transfer_inbox: false,
    delete_message: false,
    send_broadcast: false,
  },
  settings: {
    manage_users: false,
    manage_roles: false,
    manage_agenda_config: false,
    manage_inboxes: false,
    view_reports: false,
  },
});

const permissions = ref(defaultPermissions());

const PRESET_PERMISSIONS_MAP = {
  recepcionista: {
    beclinic_role: 'gerente',
    patients: {
      scope: 'all',
      view: true,
      create: true,
      edit: true,
      delete: false,
      view_clinical_notes: false,
      create_clinical_notes: false,
      sign_clinical_notes: false,
      delete_clinical_notes: false,
      view_treatment_plans: true,
      manage_treatment_plans: false,
      view_consents: true,
      manage_consents: false,
      view_documents: true,
      manage_documents: false,
      view_exams: true,
      manage_exams: false,
      view_audit: false,
      view_timeline: true,
    },
    agenda: {
      scope: 'all',
      view: true,
      create_event: true,
      edit_event: true,
      cancel_event: true,
      drag_and_drop: true,
      manage_blocks: false,
      view_notifications: true,
      manage_notifications: false,
    },
    financial: {
      view_transactions: true,
      create_transaction: true,
      delete_transaction: false,
      view_estimates: true,
      create_estimate: false,
      edit_estimate: false,
      approve_estimate: false,
      delete_estimate: false,
      view_cashflow: false,
      export_cashflow: false,
    },
    chat: {
      view_all: true,
      view_unassigned: true,
      reply: true,
      assign_conversation: true,
      transfer_inbox: true,
      delete_message: false,
      send_broadcast: false,
    },
    settings: {
      manage_users: false,
      manage_roles: false,
      manage_agenda_config: false,
      manage_inboxes: false,
      view_reports: false,
    },
  },
  especialista: {
    beclinic_role: 'especialista',
    patients: {
      scope: 'own',
      view: true,
      create: true,
      edit: true,
      delete: false,
      view_clinical_notes: true,
      create_clinical_notes: true,
      sign_clinical_notes: true,
      delete_clinical_notes: true,
      view_treatment_plans: true,
      manage_treatment_plans: true,
      view_consents: true,
      manage_consents: true,
      view_documents: true,
      manage_documents: true,
      view_exams: true,
      manage_exams: true,
      view_audit: true,
      view_timeline: true,
    },
    agenda: {
      scope: 'own',
      view: true,
      create_event: true,
      edit_event: true,
      cancel_event: true,
      drag_and_drop: true,
      manage_blocks: true,
      view_notifications: true,
      manage_notifications: false,
    },
    financial: {
      view_transactions: true,
      create_transaction: true,
      delete_transaction: false,
      view_estimates: true,
      create_estimate: true,
      edit_estimate: true,
      approve_estimate: false,
      delete_estimate: false,
      view_cashflow: false,
      export_cashflow: false,
    },
    chat: {
      view_all: false,
      view_unassigned: false,
      reply: true,
      assign_conversation: false,
      transfer_inbox: false,
      delete_message: false,
      send_broadcast: false,
    },
    settings: {
      manage_users: false,
      manage_roles: false,
      manage_agenda_config: false,
      manage_inboxes: false,
      view_reports: false,
    },
  },
  gerente: {
    beclinic_role: 'gerente',
    patients: {
      scope: 'all',
      view: true,
      create: true,
      edit: true,
      delete: true,
      view_clinical_notes: true,
      create_clinical_notes: true,
      sign_clinical_notes: true,
      delete_clinical_notes: true,
      view_treatment_plans: true,
      manage_treatment_plans: true,
      view_consents: true,
      manage_consents: true,
      view_documents: true,
      manage_documents: true,
      view_exams: true,
      manage_exams: true,
      view_audit: true,
      view_timeline: true,
    },
    agenda: {
      scope: 'all',
      view: true,
      create_event: true,
      edit_event: true,
      cancel_event: true,
      drag_and_drop: true,
      manage_blocks: true,
      view_notifications: true,
      manage_notifications: true,
    },
    financial: {
      view_transactions: true,
      create_transaction: true,
      delete_transaction: true,
      view_estimates: true,
      create_estimate: true,
      edit_estimate: true,
      approve_estimate: true,
      delete_estimate: true,
      view_cashflow: true,
      export_cashflow: true,
    },
    chat: {
      view_all: true,
      view_unassigned: true,
      reply: true,
      assign_conversation: true,
      transfer_inbox: true,
      delete_message: true,
      send_broadcast: true,
    },
    settings: {
      manage_users: true,
      manage_roles: true,
      manage_agenda_config: true,
      manage_inboxes: false,
      view_reports: true,
    },
  },
  sdr: {
    beclinic_role: 'especialista',
    patients: {
      scope: 'all',
      view: true,
      create: true,
      edit: false,
      delete: false,
      view_clinical_notes: false,
      create_clinical_notes: false,
      sign_clinical_notes: false,
      delete_clinical_notes: false,
      view_treatment_plans: false,
      manage_treatment_plans: false,
      view_consents: false,
      manage_consents: false,
      view_documents: false,
      manage_documents: false,
      view_exams: false,
      manage_exams: false,
      view_audit: false,
      view_timeline: true,
    },
    agenda: {
      scope: 'all',
      view: true,
      create_event: true,
      edit_event: true,
      cancel_event: true,
      drag_and_drop: false,
      manage_blocks: false,
      view_notifications: false,
      manage_notifications: false,
    },
    financial: {
      view_transactions: false,
      create_transaction: false,
      delete_transaction: false,
      view_estimates: true,
      create_estimate: true,
      edit_estimate: true,
      approve_estimate: false,
      delete_estimate: false,
      view_cashflow: false,
      export_cashflow: false,
    },
    chat: {
      view_all: true,
      view_unassigned: true,
      reply: true,
      assign_conversation: true,
      transfer_inbox: false,
      delete_message: false,
      send_broadcast: true,
    },
    settings: {
      manage_users: false,
      manage_roles: false,
      manage_agenda_config: false,
      manage_inboxes: false,
      view_reports: false,
    },
  },
};

// Module display config
const MODULES = [
  {
    key: 'patients',
    label: 'Pacientes / Prontuário',
    icon: '🏥',
    permissions: [
      {
        key: 'scope',
        label: 'Escopo',
        type: 'select',
        options: [
          { value: 'all', label: 'Todos' },
          { value: 'own', label: 'Apenas os seus' },
        ],
      },
      { key: 'view', label: 'Ver lista e prontuário' },
      { key: 'create', label: 'Cadastrar paciente' },
      { key: 'edit', label: 'Editar dados cadastrais' },
      { key: 'delete', label: 'Arquivar/excluir paciente' },
      { key: 'view_clinical_notes', label: 'Ver evoluções clínicas' },
      { key: 'create_clinical_notes', label: 'Criar evolução clínica' },
      { key: 'sign_clinical_notes', label: 'Assinar evolução clínica' },
      { key: 'delete_clinical_notes', label: 'Deletar rascunho de evolução' },
      { key: 'view_treatment_plans', label: 'Ver planos de tratamento' },
      { key: 'manage_treatment_plans', label: 'Criar/editar/aprovar planos' },
      { key: 'view_consents', label: 'Ver consentimentos' },
      {
        key: 'manage_consents',
        label: 'Criar, assinar e revogar consentimentos',
      },
      { key: 'view_documents', label: 'Ver documentos' },
      { key: 'manage_documents', label: 'Gerar e excluir documentos' },
      { key: 'view_exams', label: 'Ver exames e imagens' },
      { key: 'manage_exams', label: 'Upload/deleção de exames' },
      { key: 'view_audit', label: 'Ver log de auditoria' },
      { key: 'view_timeline', label: 'Ver timeline do paciente' },
    ],
  },
  {
    key: 'agenda',
    label: 'Agenda',
    icon: '📅',
    permissions: [
      {
        key: 'scope',
        label: 'Escopo',
        type: 'select',
        options: [
          { value: 'all', label: 'Todos os especialistas' },
          { value: 'own', label: 'Apenas os seus eventos' },
        ],
      },
      { key: 'view', label: 'Ver agenda' },
      { key: 'create_event', label: 'Criar agendamento' },
      { key: 'edit_event', label: 'Editar agendamento' },
      { key: 'cancel_event', label: 'Cancelar agendamento' },
      { key: 'drag_and_drop', label: 'Mover via drag-and-drop' },
      { key: 'manage_blocks', label: 'Gerenciar bloqueios e folgas' },
      { key: 'view_notifications', label: 'Ver histórico de notificações' },
      {
        key: 'manage_notifications',
        label: 'Configurar regras de notificação',
      },
    ],
  },
  {
    key: 'financial',
    label: 'Financeiro',
    icon: '💰',
    permissions: [
      { key: 'view_transactions', label: 'Ver transações' },
      { key: 'create_transaction', label: 'Registrar pagamento/cobrança' },
      { key: 'delete_transaction', label: 'Excluir transação' },
      { key: 'view_estimates', label: 'Ver orçamentos' },
      { key: 'create_estimate', label: 'Criar orçamento' },
      { key: 'edit_estimate', label: 'Editar orçamento' },
      { key: 'approve_estimate', label: 'Aprovar orçamento' },
      { key: 'delete_estimate', label: 'Excluir orçamento' },
      { key: 'view_cashflow', label: 'Ver relatório de caixa' },
      { key: 'export_cashflow', label: 'Exportar relatório financeiro' },
    ],
  },
  {
    key: 'chat',
    label: 'Chat / Conversas',
    icon: '💬',
    permissions: [
      { key: 'view_all', label: 'Ver todas as conversas' },
      { key: 'view_unassigned', label: 'Ver conversas não atribuídas' },
      { key: 'reply', label: 'Responder conversas' },
      { key: 'assign_conversation', label: 'Atribuir conversa' },
      { key: 'transfer_inbox', label: 'Transferir entre inboxes' },
      { key: 'delete_message', label: 'Deletar mensagens' },
      { key: 'send_broadcast', label: 'Disparar campanhas' },
    ],
  },
  {
    key: 'settings',
    label: 'Configurações',
    icon: '⚙️',
    permissions: [
      { key: 'manage_users', label: 'Gerenciar usuários' },
      { key: 'manage_roles', label: 'Gerenciar perfis RBAC' },
      { key: 'manage_agenda_config', label: 'Configurar agenda' },
      { key: 'manage_inboxes', label: 'Ver inboxes' },
      { key: 'view_reports', label: 'Ver relatórios' },
    ],
  },
];

// Initialize on mount or when role changes
const initForm = () => {
  if (props.mode === 'edit' && props.role) {
    formName.value = props.role.name;
    formBeclinicRole.value = props.role.beclinic_role || 'gerente';
    permissions.value = JSON.parse(
      JSON.stringify({
        ...defaultPermissions(),
        ...props.role.permissions,
      })
    );
    activeTab.value = 'custom';
  } else {
    formName.value = '';
    formBeclinicRole.value = 'gerente';
    permissions.value = defaultPermissions();
    selectedPreset.value = null;
    activeTab.value = 'preset';
  }
};

initForm();

watch(() => props.role, initForm, { immediate: false });

const selectPreset = preset => {
  selectedPreset.value = preset.key;
  const presetPerms = PRESET_PERMISSIONS_MAP[preset.key];
  formBeclinicRole.value = presetPerms.beclinic_role;
  // Copy preset permissions (excluding beclinic_role)
  const { beclinic_role: _br, ...perms } = presetPerms;
  permissions.value = JSON.parse(JSON.stringify(perms));
};

const isValid = computed(() => formName.value.trim().length > 0);

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  try {
    const payload = {
      name: formName.value.trim(),
      beclinic_role: formBeclinicRole.value,
      permissions: permissions.value,
    };

    if (props.mode === 'edit' && props.role) {
      await BeClinicRolesAPI.update(props.role.id, payload);
      useAlert(`Perfil "${payload.name}" atualizado com sucesso.`);
    } else {
      await BeClinicRolesAPI.create(payload);
      useAlert(`Perfil "${payload.name}" criado com sucesso.`);
    }
    emit('saved');
  } catch {
    useAlert('Erro ao salvar o perfil.');
  } finally {
    isSaving.value = false;
  }
};

const title = computed(() =>
  props.mode === 'edit' ? 'Editar Perfil' : 'Novo Perfil'
);
</script>

<template>
  <div class="role-form-modal">
    <!-- Modal Header -->
    <div class="modal-header">
      <h2 class="modal-title">{{ title }}</h2>
      <p class="modal-subtitle">
        Configure o nome, nível de acesso e permissões granulares deste perfil.
      </p>
    </div>

    <!-- Tabs: Preset vs Custom -->
    <div v-if="mode === 'add'" class="mode-tabs">
      <button
        class="mode-tab"
        :class="{ active: activeTab === 'preset' }"
        @click="activeTab = 'preset'"
      >
        ✨ Perfis Padrão
      </button>
      <button
        class="mode-tab"
        :class="{ active: activeTab === 'custom' }"
        @click="activeTab = 'custom'"
      >
        🔧 Customizado
      </button>
    </div>

    <!-- PRESET TAB -->
    <template v-if="activeTab === 'preset'">
      <div class="preset-grid">
        <div
          v-for="preset in PRESET_OPTIONS"
          :key="preset.key"
          class="preset-card"
          :class="{ selected: selectedPreset === preset.key }"
          @click="selectPreset(preset)"
        >
          <span class="preset-icon">{{ preset.icon }}</span>
          <span class="preset-label">{{ preset.label }}</span>
          <span class="preset-desc">{{ preset.description }}</span>
          <span class="preset-role-badge">{{
            { gerente: 'Gerente', especialista: 'Especialista', dono: 'Dono' }[
              preset.beclinic_role
            ]
          }}</span>
        </div>
      </div>

      <!-- Name field after preset selected -->
      <div v-if="selectedPreset" class="preset-name-row">
        <label class="form-label">Nome do Perfil <span class="required">*</span></label>
        <input
          v-model="formName"
          class="form-input"
          :placeholder="`Ex: ${PRESET_OPTIONS.find(p => p.key === selectedPreset)?.label}`"
          maxlength="60"
        />
        <p class="field-hint">
          Você pode customizar o nome para refletir o contexto da sua clínica.
        </p>
      </div>
    </template>

    <!-- CUSTOM TAB -->
    <template v-else>
      <!-- Basic Info -->
      <div class="form-group">
        <label class="form-label">Nome do Perfil <span class="required">*</span></label>
        <input
          v-model="formName"
          class="form-input"
          placeholder="Ex: Fisioterapeuta, Auxiliar, Coordenador..."
          maxlength="60"
        />
      </div>

      <div class="form-group">
        <label class="form-label">Nível Base</label>
        <select v-model="formBeclinicRole" class="form-select">
          <option value="gerente">
            Gerente — acesso amplo, sem restrição de escopo
          </option>
          <option value="especialista">
            Especialista — acesso configurável, pode ter escopo próprio
          </option>
        </select>
      </div>

      <!-- Permissions by Module -->
      <div class="permissions-editor">
        <div v-for="mod in MODULES" :key="mod.key" class="perm-module-block">
          <div class="perm-module-header">
            <span class="perm-module-icon">{{ mod.icon }}</span>
            <span class="perm-module-label">{{ mod.label }}</span>
          </div>
          <div class="perm-fields">
            <div
              v-for="perm in mod.permissions"
              :key="perm.key"
              class="perm-field"
            >
              <template v-if="perm.type === 'select'">
                <label class="perm-label">{{ perm.label }}</label>
                <select
                  v-model="permissions[mod.key][perm.key]"
                  class="perm-select"
                >
                  <option
                    v-for="opt in perm.options"
                    :key="opt.value"
                    :value="opt.value"
                  >
                    {{ opt.label }}
                  </option>
                </select>
              </template>
              <template v-else>
                <label class="perm-toggle-label">
                  <Switch
                    :model-value="!!(permissions[mod.key] && permissions[mod.key][perm.key])"
                    @update:model-value="val => (permissions[mod.key][perm.key] = val)"
                  />
                  <span class="perm-label">{{ perm.label }}</span>
                </label>
              </template>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- Footer Actions -->
    <div class="modal-footer">
      <Button label="Cancelar" slate @click="emit('close')" />
      <Button
        :label="mode === 'edit' ? 'Salvar Alterações' : 'Criar Perfil'"
        :is-loading="isSaving"
        :disabled="!isValid"
        @click="save"
      />
    </div>
  </div>
</template>

<style scoped>
.role-form-modal {
  padding: 1.5rem;
  max-height: 85vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  min-width: 560px;
  max-width: 680px;
}

.modal-header {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}
.modal-title {
  font-size: 1.125rem;
  font-weight: 700;
  color: var(--color-heading);
  margin: 0;
}
.modal-subtitle {
  font-size: 0.8125rem;
  color: var(--color-body);
  margin: 0;
}

/* Mode tabs */
.mode-tabs {
  display: flex;
  gap: 0.5rem;
  background: var(--color-bg-2);
  border-radius: 10px;
  padding: 4px;
}
.mode-tab {
  flex: 1;
  padding: 0.5rem 1rem;
  border: none;
  background: transparent;
  border-radius: 8px;
  font-size: 0.8125rem;
  font-weight: 500;
  color: var(--color-body);
  cursor: pointer;
  transition: all 0.15s ease;
}
.mode-tab.active {
  background: var(--color-bg-1);
  color: var(--color-woot);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
}

/* Preset grid */
.preset-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
}
.preset-card {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 1rem 1.125rem;
  border: 2px solid var(--color-border-light);
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.15s ease;
  background: var(--color-bg-1);
}
.preset-card:hover {
  border-color: var(--color-woot-400);
  background: #f5f3ff;
}
.preset-card.selected {
  border-color: var(--color-woot);
  background: #ede9fe;
}
.preset-icon {
  font-size: 1.25rem;
  margin-bottom: 0.25rem;
}
.preset-label {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-heading);
}
.preset-desc {
  font-size: 0.75rem;
  color: var(--color-body);
  line-height: 1.4;
}
.preset-role-badge {
  margin-top: 0.25rem;
  font-size: 0.6875rem;
  font-weight: 600;
  color: #5b21b6;
  background: #ede9fe;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  width: fit-content;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.preset-name-row {
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
}
.field-hint {
  font-size: 0.75rem;
  color: var(--color-body);
  opacity: 0.75;
  margin: 0;
}

/* Form fields */
.form-group {
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
}
.form-label {
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--color-heading);
}
.required {
  color: #e11d48;
}
.form-input,
.form-select {
  padding: 0.5rem 0.75rem;
  border: 1px solid var(--color-border-light);
  border-radius: 8px;
  font-size: 0.875rem;
  color: var(--color-heading);
  background: var(--color-bg-1);
  transition: border-color 0.15s;
  outline: none;
}
.form-input:focus,
.form-select:focus {
  border-color: var(--color-woot);
}

/* Permissions editor */
.permissions-editor {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.perm-module-block {
  border: 1px solid var(--color-border-light);
  border-radius: 10px;
  overflow: hidden;
}
.perm-module-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.625rem 1rem;
  background: var(--color-bg-2);
  border-bottom: 1px solid var(--color-border-light);
}
.perm-module-icon {
  font-size: 1rem;
}
.perm-module-label {
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--color-heading);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.perm-fields {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
}
.perm-field {
  display: flex;
  align-items: center;
}
.perm-toggle-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
}
.perm-checkbox {
  width: 15px;
  height: 15px;
  flex-shrink: 0;
  accent-color: var(--color-woot);
}
.perm-label {
  font-size: 0.8rem;
  color: var(--color-body);
}
.perm-select {
  padding: 0.25rem 0.5rem;
  border: 1px solid var(--color-border-light);
  border-radius: 6px;
  font-size: 0.8rem;
  color: var(--color-heading);
  background: var(--color-bg-1);
  outline: none;
  width: 100%;
}

/* Footer */
.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.75rem;
  padding-top: 0.5rem;
  border-top: 1px solid var(--color-border-light);
}
</style>
