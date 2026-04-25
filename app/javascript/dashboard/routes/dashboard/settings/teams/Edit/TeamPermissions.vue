<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();

const teamId = computed(() => route.params.teamId);
const team = computed(() => store.getters['teams/getTeam'](teamId.value));

// RBAC preset definitions — mirroring backend PRESET_PERMISSIONS
const BUILTIN_PRESETS = {
  recepcionista: {
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

// ── RBAC preset roles (display metadata) ──
const PRESET_ROLES = [
  {
    id: 'recepcionista',
    label: 'Recepcionista',
    description: 'Agenda, cadastro e visualização. Sem acesso clínico.',
    icon: 'i-lucide-clipboard',
    color: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
    iconColor: 'text-blue-400',
  },
  {
    id: 'especialista',
    label: 'Especialista',
    description: 'Acesso clínico completo. Escopo próprio de pacientes.',
    icon: 'i-lucide-stethoscope',
    color: 'bg-violet-500/10 text-violet-400 border-violet-500/20',
    iconColor: 'text-violet-400',
  },
  {
    id: 'gerente',
    label: 'Gerente',
    description:
      'Acesso total: clínico, financeiro, relatórios e configurações.',
    icon: 'i-lucide-shield-check',
    color: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    iconColor: 'text-emerald-400',
  },
  {
    id: 'sdr',
    label: 'SDR / Comercial',
    description: 'Captação, orçamentos e agenda. Sem acesso ao prontuário.',
    icon: 'i-lucide-trending-up',
    color: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
    iconColor: 'text-amber-400',
  },
];

// ── Permission sections for custom editing ──
const PERMISSION_SECTIONS = [
  {
    module: 'patients',
    label: 'Pacientes',
    icon: 'i-lucide-users',
    permissions: [
      { key: 'view', label: 'Visualizar pacientes' },
      { key: 'create', label: 'Criar pacientes' },
      { key: 'edit', label: 'Editar dados cadastrais' },
      { key: 'delete', label: 'Excluir pacientes' },
      { key: 'view_clinical_notes', label: 'Ver evoluções clínicas' },
      { key: 'create_clinical_notes', label: 'Criar evoluções' },
      { key: 'sign_clinical_notes', label: 'Assinar evoluções' },
      { key: 'delete_clinical_notes', label: 'Excluir evoluções' },
      { key: 'view_treatment_plans', label: 'Ver planos de tratamento' },
      {
        key: 'manage_treatment_plans',
        label: 'Gerenciar planos de tratamento',
      },
      { key: 'view_consents', label: 'Ver consentimentos' },
      { key: 'manage_consents', label: 'Gerenciar consentimentos' },
      { key: 'view_documents', label: 'Ver documentos' },
      { key: 'manage_documents', label: 'Gerenciar documentos' },
      { key: 'view_exams', label: 'Ver exames e imagens' },
      { key: 'manage_exams', label: 'Gerenciar exames' },
      { key: 'view_audit', label: 'Acessar aba de Auditoria' },
    ],
  },
  {
    module: 'agenda',
    label: 'Agenda',
    icon: 'i-lucide-calendar',
    permissions: [
      { key: 'view', label: 'Visualizar agenda' },
      { key: 'create_event', label: 'Criar eventos' },
      { key: 'edit_event', label: 'Editar eventos' },
      { key: 'cancel_event', label: 'Cancelar eventos' },
      { key: 'drag_and_drop', label: 'Arrastar e reorganizar' },
      { key: 'manage_blocks', label: 'Gerenciar bloqueios' },
    ],
  },
  {
    module: 'financial',
    label: 'Financeiro',
    icon: 'i-lucide-dollar-sign',
    permissions: [
      { key: 'view_transactions', label: 'Ver transações' },
      { key: 'create_transaction', label: 'Criar transações' },
      { key: 'delete_transaction', label: 'Excluir transações' },
      { key: 'view_estimates', label: 'Ver orçamentos' },
      { key: 'create_estimate', label: 'Criar orçamentos' },
      { key: 'edit_estimate', label: 'Editar orçamentos' },
      { key: 'approve_estimate', label: 'Aprovar orçamentos' },
      { key: 'delete_estimate', label: 'Excluir orçamentos' },
      { key: 'view_cashflow', label: 'Ver fluxo de caixa' },
      { key: 'export_cashflow', label: 'Exportar financeiro' },
    ],
  },
  {
    module: 'chat',
    label: 'Chat / Conversas',
    icon: 'i-lucide-message-circle',
    permissions: [
      { key: 'view_all', label: 'Ver todas as conversas' },
      { key: 'reply', label: 'Responder conversas' },
      { key: 'assign_conversation', label: 'Atribuir conversas' },
      { key: 'delete_message', label: 'Excluir mensagens' },
      { key: 'send_broadcast', label: 'Enviar broadcast' },
    ],
  },
  {
    module: 'settings',
    label: 'Configurações',
    icon: 'i-lucide-settings',
    permissions: [
      { key: 'manage_users', label: 'Gerenciar usuários' },
      { key: 'manage_roles', label: 'Gerenciar funções e permissões' },
      { key: 'manage_agenda_config', label: 'Configurar agenda' },
      { key: 'view_reports', label: 'Ver relatórios' },
    ],
  },
];

// ── State ──
const isSaving = ref(false);
const isLoadingPreset = ref(false);
const selectedPresetId = ref(null);
const permissions = ref({});
const expandedSections = ref(new Set(['patients']));
const mode = ref('preset'); // 'preset' | 'custom'

const togglePerm = (module, key) => {
  if (!permissions.value[module]) permissions.value[module] = {};
  permissions.value[module][key] = !permissions.value[module][key];
};

const toggleSection = id => {
  const next = new Set(expandedSections.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expandedSections.value = next;
};

const toggleAllModule = module => {
  const section = PERMISSION_SECTIONS.find(s => s.module === module);
  const total = section.permissions.length;
  const checked = section.permissions.filter(p => permissions.value[module]?.[p.key]).length;
  const isAll = checked === total;

  if (!permissions.value[module]) permissions.value[module] = {};

  section.permissions.forEach(p => {
    permissions.value[module][p.key] = !isAll;
  });
};

// ── Apply preset from local data ──
const applyPreset = presetId => {
  isLoadingPreset.value = true;
  try {
    const preset = BUILTIN_PRESETS[presetId];
    if (!preset) throw new Error('Preset not found');
    permissions.value = JSON.parse(JSON.stringify(preset));
    selectedPresetId.value = presetId;
    mode.value = 'custom'; // move to custom view after loading
  } catch {
    useAlert('Erro ao carregar preset. Tente novamente.');
  } finally {
    isLoadingPreset.value = false;
  }
};

const getPresetActiveCount = presetId => {
  const preset = BUILTIN_PRESETS[presetId];
  if (!preset) return 0;
  let count = 0;
  Object.values(preset).forEach(mod => {
    Object.values(mod).forEach(val => {
      if (val === true) count++;
    });
  });
  return count;
};

// Mount: initialize permissions from team data
onMounted(() => {
  if (team.value?.permissions && Object.keys(team.value.permissions).length) {
    permissions.value = JSON.parse(JSON.stringify(team.value.permissions));
  }
});

// ── Save ──
const savePermissions = async () => {
  isSaving.value = true;
  try {
    await store.dispatch('teams/update', {
      id: teamId.value,
      permissions: permissions.value,
    });
    useAlert('Permissões salvas com sucesso!');
    router.push({
      name: 'settings_teams_edit_finish',
      params: { teamId: teamId.value },
    });
  } catch {
    useAlert('Erro ao salvar permissões. Tente novamente.');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="h-full w-full col-span-6 overflow-y-auto">
    <!-- Header -->
    <div class="px-8 pt-8 pb-4 border-b border-n-weak">
      <h2 class="text-lg font-semibold text-n-slate-12">Permissões RBAC</h2>
      <p class="text-sm text-n-slate-11 mt-0.5">
        Configure o que os membros deste time podem ver e fazer no BeClinic.
      </p>
    </div>

    <div class="px-8 py-6 space-y-6">
      <!-- Mode toggle -->
      <div class="flex gap-2 p-1 bg-n-slate-3 rounded-lg w-fit">
        <button
          class="px-4 py-1.5 rounded-md text-sm font-medium transition-all"
          :class="[
            mode === 'preset'
              ? 'bg-n-slate-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12',
          ]"
          @click="mode = 'preset'"
        >
          Perfis Prontos
        </button>
        <button
          class="px-4 py-1.5 rounded-md text-sm font-medium transition-all"
          :class="[
            mode === 'custom'
              ? 'bg-n-slate-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12',
          ]"
          @click="mode = 'custom'"
        >
          Personalizado
        </button>
      </div>

      <!-- ── PRESET MODE ── -->
      <div v-if="mode === 'preset'" class="space-y-3">
        <p class="text-xs text-n-slate-11 uppercase tracking-wider font-medium">
          Selecione um perfil para aplicar ao time:
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <button
            v-for="preset in PRESET_ROLES"
            :key="preset.id"
            class="flex items-start gap-3 p-4 rounded-xl border text-left transition-all"
            :class="[
              selectedPresetId === preset.id
                ? preset.color + ' border-current'
                : 'border-n-weak hover:border-n-slate-7 bg-n-slate-2 hover:bg-n-slate-3',
              isLoadingPreset ? 'opacity-50 cursor-wait' : '',
            ]"
            @click="applyPreset(preset.id)"
          >
            <i
              class="w-5 h-5 flex-shrink-0 mt-0.5"
              :class="[
                preset.icon,
                selectedPresetId === preset.id ? '' : 'text-n-slate-11',
              ]"
            />
            <div>
              <span class="flex items-center gap-2 text-sm font-semibold">
                {{ preset.label }}
                <span class="px-1.5 py-0.5 rounded-md bg-n-slate-3 text-[10px] font-medium text-n-slate-11">
                  {{ getPresetActiveCount(preset.id) }} permissões
                </span>
              </span>
              <span class="text-xs text-n-slate-11 leading-relaxed mt-1 block">
                {{ preset.description }}
              </span>
            </div>
          </button>
        </div>

        <div
          v-if="selectedPresetId"
          class="flex items-center gap-2 p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-sm"
        >
          <i class="i-lucide-check-circle w-4 h-4 flex-shrink-0" />
          Perfil "<strong>{{
            PRESET_ROLES.find(p => p.id === selectedPresetId)?.label
          }}</strong>" carregado.
          <button class="underline ml-1" @click="mode = 'custom'">
            Personalizar →
          </button>
        </div>
      </div>

      <!-- ── CUSTOM MODE ── -->
      <div v-else class="space-y-3">
        <p class="text-xs text-n-slate-11 uppercase tracking-wider font-medium">
          Permissões individuais:
        </p>

        <!-- Section accordion -->
        <div
          v-for="section in PERMISSION_SECTIONS"
          :key="section.module"
          class="border border-n-weak rounded-xl overflow-hidden"
        >
          <!-- Section header -->
          <div
            class="flex items-center justify-between px-4 py-3 bg-n-slate-2 border-b border-n-weak transition-colors"
          >
            <button
              class="flex flex-1 items-center gap-2 text-left hover:text-woot-500 transition-colors"
              @click="toggleSection(section.module)"
            >
              <i class="w-4 h-4 text-n-slate-11" :class="[section.icon]" />
              <span class="text-sm font-semibold text-n-slate-12">
                {{ section.label }}
              </span>
              <span class="text-xs text-n-slate-11">
                ({{
                  section.permissions.filter(
                    p => permissions[section.module]?.[p.key]
                  ).length
                }}/{{ section.permissions.length }})
              </span>
            </button>
            <div class="flex items-center gap-4">
              <button
                class="text-[11px] font-semibold px-2.5 py-1 rounded-[6px] border hover:bg-n-slate-3 transition-colors"
                :class="
                  section.permissions.filter(p => permissions[section.module]?.[p.key]).length === section.permissions.length
                    ? 'text-woot-500 border-woot-500/30 bg-woot-500/10'
                    : 'text-n-slate-9 border-n-slate-4'
                "
                @click="toggleAllModule(section.module)"
              >
                {{ section.permissions.filter(p => permissions[section.module]?.[p.key]).length === section.permissions.length ? 'Desmarcar todos' : 'Marcar todos' }}
              </button>
              <button @click="toggleSection(section.module)">
                <i
                  class="w-4 h-4 text-n-slate-11 block transition-transform"
                  :class="[
                    expandedSections.has(section.module)
                      ? 'i-lucide-chevron-up'
                      : 'i-lucide-chevron-down',
                  ]"
                />
              </button>
            </div>
          </div>

          <!-- Permission toggles -->
          <div
            v-show="expandedSections.has(section.module)"
            class="divide-y divide-n-weak"
          >
            <div
              v-for="perm in section.permissions"
              :key="perm.key"
              class="flex items-center justify-between px-4 py-2.5 hover:bg-n-slate-2 transition-colors"
            >
              <span class="text-sm text-n-slate-11">{{ perm.label }}</span>
              <Switch
                :model-value="!!(permissions[section.module] && permissions[section.module][perm.key])"
                @update:model-value="togglePerm(section.module, perm.key)"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- ── Actions ── -->
      <div class="flex justify-end gap-3 pt-2 border-t border-n-weak">
        <button
          class="px-4 py-2 rounded-lg text-sm text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3 transition-colors"
          @click="router.back()"
        >
          Voltar
        </button>
        <button
          :disabled="isSaving || (mode === 'preset' && !selectedPresetId)"
          class="flex items-center gap-2 px-5 py-2 rounded-lg text-sm font-medium transition-all"
          :class="[
            isSaving || (mode === 'preset' && !selectedPresetId)
              ? 'bg-n-slate-4 text-n-slate-9 cursor-not-allowed'
              : 'bg-woot-500 hover:bg-woot-600 text-white',
          ]"
          @click="savePermissions"
        >
          <i v-if="isSaving" class="i-lucide-loader-2 animate-spin w-4 h-4" />
          <i v-else class="i-lucide-save w-4 h-4" />
          Salvar Permissões
        </button>
      </div>
    </div>
  </div>
</template>
