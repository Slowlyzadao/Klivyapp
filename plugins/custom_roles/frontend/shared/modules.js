/**
 * Catálogo central dos módulos do Klivy e suas sub-permissões.
 *
 * Cada módulo tem `key`, `label`, `icon`, `description?` e UMA das duas
 * formas de declarar permissões:
 *
 *   1) `permissions: Permission[]`           — lista plana
 *   2) `groups: Group[]`                     — agrupado, com header próprio
 *
 * Um Group tem `key`, `label`, `icon?`, `permissions: Permission[]`. A UI
 * renderiza grupos como subseções colapsáveis com seu próprio "Marcar todos /
 * Desmarcar todos" e contador de ativas, e fica organizada como
 * Módulo > Grupo > Permissão.
 *
 * Independente do formato, cada Permission é `{ key, label, description? }`.
 *
 * Regra: se TODAS as permissões de um módulo estão `false`, o módulo
 * desaparece do menu lateral (toggle pai esconde tudo).
 */

export const MODULES = [
  {
    key: 'inbox',
    label: 'Caixa de Entrada',
    icon: 'i-lucide-inbox',
    description: 'Notificações pessoais, menções e atribuições.',
    permissions: [
      { key: 'view', label: 'Ver caixa de entrada' },
      { key: 'mark_read', label: 'Marcar como lido' },
    ],
  },
  {
    key: 'chat',
    label: 'Conversas',
    icon: 'i-lucide-message-circle',
    description: 'Tickets, conversas, atribuições, painel e ações sobre o contato.',
    groups: [
      {
        key: 'actions',
        label: 'Ações da conversa',
        icon: 'i-lucide-message-square',
        permissions: [
          { key: 'view_all', label: 'Ver todas as conversas' },
          { key: 'view_unassigned', label: 'Ver não atribuídas' },
          { key: 'view_mentions', label: 'Ver menções' },
          { key: 'reply', label: 'Responder conversas' },
          { key: 'assign_conversation', label: 'Atribuir conversas' },
          { key: 'delete_message', label: 'Excluir mensagens' },
          { key: 'send_broadcast', label: 'Enviar broadcast' },
        ],
      },
      {
        key: 'panel',
        label: 'Painel da conversa',
        icon: 'i-lucide-panel-right',
        permissions: [
          { key: 'view_conversation_actions', label: 'Ver ações da conversa' },
          { key: 'use_macros', label: 'Usar macros' },
          { key: 'view_conversation_info', label: 'Ver informação da conversa' },
          { key: 'view_contact_attributes', label: 'Ver atributos do contato' },
          { key: 'view_contact_notes', label: 'Ver notas do contato' },
          { key: 'view_previous_conversations', label: 'Ver conversas anteriores' },
          { key: 'view_participants', label: 'Ver participantes da conversa' },
        ],
      },
      {
        key: 'contact_header',
        label: 'Ações do contato',
        icon: 'i-lucide-user-cog',
        permissions: [
          { key: 'view_patient_record', label: 'Ver prontuário' },
          { key: 'create_appointment', label: 'Agendar consulta a partir da conversa' },
          { key: 'edit_contact', label: 'Editar contato' },
          { key: 'merge_contact', label: 'Mesclar contato' },
          { key: 'manage_waiting_list', label: 'Adicionar à lista de espera' },
          { key: 'view_contact_profile', label: 'Abrir página do contato' },
          { key: 'delete_contact', label: 'Excluir contato' },
        ],
      },
    ],
  },
  {
    key: 'captain',
    label: 'BEA (IA)',
    icon: 'i-lucide-sparkles',
    description: 'Assistente de IA, FAQs, documentos, cenários e ferramentas.',
    permissions: [
      { key: 'view', label: 'Acessar a BEA' },
      { key: 'manage_faqs', label: 'Gerenciar FAQs' },
      { key: 'manage_documents', label: 'Gerenciar documentos' },
      { key: 'manage_scenarios', label: 'Gerenciar cenários' },
      { key: 'use_playground', label: 'Usar playground' },
      { key: 'manage_inboxes', label: 'Gerenciar caixas de entrada' },
      { key: 'manage_tools', label: 'Gerenciar ferramentas' },
      { key: 'manage_settings', label: 'Configurar BEA' },
      { key: 'manage_follow_ups', label: 'Gerenciar follow-ups da Bea' },
      {
        key: 'manage_templates',
        label: 'Gerenciar notificações internas',
        description:
          'Templates pré-definidos que a Beatriz dispara no Chat Interno (zero token). Quem tem esta perm edita texto, destino e ativa/desativa.',
      },
    ],
  },
  {
    key: 'internal_chat',
    label: 'Chat Interno',
    icon: 'i-lucide-message-square',
    description:
      'Chat interno entre profissionais — salas, DMs, menções e stickers. Acesso a sala específica é auto-gateado por membership.',
    permissions: [
      { key: 'view', label: 'Acessar o Chat Interno' },
      { key: 'create_room', label: 'Criar salas / iniciar conversas' },
      { key: 'manage_stickers', label: 'Gerenciar stickers da conta' },
      {
        key: 'manage_memberships',
        label: 'Gerenciar membros de salas (futuro)',
        description:
          'Reservado pra release futuro — quando ativo vai restringir add/remove de membros e mudanças de role só pra users com esta perm + papel owner/admin da sala. Hoje a checagem ainda é só por papel da sala (owner/admin) + admin da conta como bypass. Adicionar a perm em roles existentes não muda comportamento atual.',
      },
    ],
  },
  {
    key: 'agenda',
    label: 'Agenda',
    icon: 'i-lucide-calendar',
    description: 'Calendário, eventos, configurações e atributos.',
    groups: [
      {
        key: 'provider',
        label: 'Profissional da agenda',
        icon: 'i-lucide-user-round',
        permissions: [
          {
            key: 'is_provider',
            label: 'É profissional / atende na agenda',
            description:
              'Quem tem este papel aparece como coluna no calendário e pode receber agendamentos. Desligue para papéis administrativos (recepção, gerência sem atendimento, financeiro).',
          },
        ],
      },
      {
        key: 'calendar',
        label: 'Calendário',
        icon: 'i-lucide-calendar-days',
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
        key: 'settings_tab',
        label: 'Configurações da agenda',
        icon: 'i-lucide-settings',
        permissions: [
          { key: 'view_settings', label: 'Acessar configurações' },
          { key: 'manage_schedules', label: 'Gerenciar horários e exceções' },
          { key: 'manage_online_booking', label: 'Gerenciar agendamento online' },
          { key: 'manage_services', label: 'Gerenciar serviços' },
        ],
      },
      {
        key: 'notifications_tab',
        label: 'Notificações automáticas',
        icon: 'i-lucide-bell',
        permissions: [
          { key: 'view_notifications', label: 'Ver notificações automáticas' },
          { key: 'manage_notifications', label: 'Gerenciar notificações automáticas' },
        ],
      },
      {
        key: 'custom_attributes_tab',
        label: 'Atributos personalizados',
        icon: 'i-lucide-code',
        permissions: [
          { key: 'manage_custom_attributes', label: 'Gerenciar atributos personalizados' },
        ],
      },
    ],
  },
  {
    key: 'patients',
    label: 'Pacientes',
    icon: 'i-lucide-users',
    description: 'Cadastro, prontuário, exames e timeline.',
    permissions: [
      { key: 'view', label: 'Visualizar pacientes' },
      { key: 'create', label: 'Criar pacientes' },
      { key: 'edit', label: 'Editar dados cadastrais' },
      { key: 'delete', label: 'Excluir pacientes' },
      { key: 'view_anamnesis', label: 'Ver anamnese' },
      { key: 'manage_anamnesis', label: 'Editar e salvar anamnese' },
      { key: 'view_clinical_notes', label: 'Ver evoluções clínicas' },
      { key: 'create_clinical_notes', label: 'Criar evoluções' },
      { key: 'sign_clinical_notes', label: 'Assinar evoluções' },
      { key: 'delete_clinical_notes', label: 'Excluir evoluções' },
      { key: 'view_treatment_plans', label: 'Ver planos de tratamento' },
      { key: 'manage_treatment_plans', label: 'Gerenciar planos de tratamento' },
      { key: 'view_consents', label: 'Ver consentimentos' },
      { key: 'manage_consents', label: 'Gerenciar consentimentos' },
      { key: 'view_documents', label: 'Ver documentos' },
      { key: 'manage_documents', label: 'Gerenciar documentos' },
      { key: 'view_exams', label: 'Ver exames e imagens' },
      { key: 'manage_exams', label: 'Gerenciar exames' },
      { key: 'view_audit', label: 'Ver auditoria' },
      { key: 'view_timeline', label: 'Ver timeline' },
      { key: 'view_financial', label: 'Ver financeiro do paciente' },
      { key: 'manage_financial', label: 'Gerenciar financeiro do paciente' },
    ],
  },
  {
    key: 'financial',
    label: 'Financeiro',
    icon: 'i-lucide-dollar-sign',
    description: 'Caixa, recebíveis, contas a pagar, DRE e relatórios.',
    permissions: [
      { key: 'view_dashboard', label: 'Ver dashboard financeiro' },
      { key: 'view_cashflow', label: 'Ver fluxo de caixa' },
      { key: 'view_receivables', label: 'Ver contas a receber' },
      { key: 'view_payables', label: 'Ver contas a pagar' },
      { key: 'view_dre', label: 'Ver DRE' },
      { key: 'view_reports', label: 'Ver relatórios financeiros' },
      { key: 'view_cash_register', label: 'Ver caixa diário' },
      { key: 'create_transaction', label: 'Criar transações' },
      { key: 'edit_transaction', label: 'Editar transações' },
      { key: 'delete_transaction', label: 'Excluir transações' },
      { key: 'manage_estimates', label: 'Gerenciar orçamentos' },
      { key: 'approve_estimate', label: 'Aprovar orçamentos' },
      { key: 'export_data', label: 'Exportar dados financeiros' },
      { key: 'manage_settings', label: 'Configurar financeiro' },
    ],
  },
  {
    key: 'contacts',
    label: 'Contatos',
    icon: 'i-lucide-contact',
    description: 'Lista de contatos, segmentações e tags.',
    permissions: [
      { key: 'view_all', label: 'Ver todos os contatos' },
      { key: 'view_active', label: 'Ver contatos ativos' },
      { key: 'create', label: 'Criar contatos' },
      { key: 'edit', label: 'Editar contatos' },
      { key: 'delete', label: 'Excluir contatos' },
      { key: 'manage_segments', label: 'Gerenciar segmentos' },
      { key: 'manage_tags', label: 'Gerenciar tags' },
      { key: 'import_export', label: 'Importar / exportar' },
    ],
  },
  {
    key: 'reports',
    label: 'Relatórios',
    icon: 'i-lucide-bar-chart-3',
    description: 'Relatórios operacionais e gerenciais.',
    permissions: [
      { key: 'view_overview', label: 'Visão geral' },
      { key: 'view_conversation', label: 'Conversas' },
      { key: 'view_agent', label: 'Por agente' },
      { key: 'view_label', label: 'Por etiqueta' },
      { key: 'view_inbox', label: 'Por caixa de entrada' },
      { key: 'view_team', label: 'Por time' },
      { key: 'view_csat', label: 'CSAT' },
      { key: 'view_sla', label: 'SLA' },
      { key: 'view_bot', label: 'Bot' },
      { key: 'view_agenda', label: 'Agenda' },
    ],
  },
  {
    key: 'campaigns',
    label: 'Campanhas',
    icon: 'i-lucide-megaphone',
    description: 'Campanhas ao vivo, SMS e WhatsApp.',
    permissions: [
      { key: 'view', label: 'Visualizar campanhas' },
      { key: 'manage_live_chat', label: 'Gerenciar Live Chat' },
      { key: 'manage_sms', label: 'Gerenciar SMS' },
      { key: 'manage_whatsapp', label: 'Gerenciar WhatsApp' },
    ],
  },
  {
    key: 'help_center',
    label: 'Central de Ajuda',
    icon: 'i-lucide-book-open',
    description: 'Portais, artigos e categorias.',
    permissions: [
      { key: 'view', label: 'Visualizar central' },
      { key: 'manage_articles', label: 'Gerenciar artigos' },
      { key: 'manage_categories', label: 'Gerenciar categorias' },
      { key: 'manage_portals', label: 'Gerenciar portais' },
    ],
  },
  {
    key: 'settings',
    label: 'Configurações',
    icon: 'i-lucide-settings',
    description: 'Usuários, funções, integrações e auditoria.',
    groups: [
      {
        key: 'account',
        label: 'Conta',
        icon: 'i-lucide-briefcase',
        permissions: [
          { key: 'account_view', label: 'Visualizar configurações da conta' },
          { key: 'account_manage', label: 'Editar configurações da conta' },
        ],
      },
      {
        key: 'users',
        label: 'Agentes',
        icon: 'i-lucide-square-user',
        permissions: [
          { key: 'users_view', label: 'Visualizar agentes' },
          { key: 'users_invite', label: 'Convidar novos agentes' },
          { key: 'users_edit', label: 'Editar agentes' },
          { key: 'users_remove', label: 'Remover agentes' },
        ],
      },
      {
        key: 'teams',
        label: 'Times',
        icon: 'i-lucide-users',
        permissions: [
          { key: 'teams_view', label: 'Visualizar times' },
          { key: 'teams_create', label: 'Criar times' },
          { key: 'teams_edit', label: 'Editar times' },
          { key: 'teams_delete', label: 'Excluir times' },
        ],
      },
      {
        key: 'inboxes',
        label: 'Caixas de entrada',
        icon: 'i-lucide-inbox',
        permissions: [
          { key: 'inboxes_view', label: 'Visualizar caixas de entrada' },
          { key: 'inboxes_create', label: 'Conectar nova caixa de entrada' },
          { key: 'inboxes_edit', label: 'Editar caixa de entrada' },
          { key: 'inboxes_delete', label: 'Excluir caixa de entrada' },
          { key: 'inboxes_manage_agents', label: 'Gerenciar agentes da caixa' },
        ],
      },
      {
        key: 'labels',
        label: 'Etiquetas',
        icon: 'i-lucide-tags',
        permissions: [
          { key: 'labels_view', label: 'Visualizar etiquetas' },
          { key: 'labels_create', label: 'Criar etiquetas' },
          { key: 'labels_edit', label: 'Editar etiquetas' },
          { key: 'labels_delete', label: 'Excluir etiquetas' },
        ],
      },
      {
        key: 'custom_attributes',
        label: 'Atributos personalizados',
        icon: 'i-lucide-code',
        permissions: [
          { key: 'custom_attributes_view', label: 'Visualizar atributos' },
          { key: 'custom_attributes_create', label: 'Criar atributos' },
          { key: 'custom_attributes_edit', label: 'Editar atributos' },
          { key: 'custom_attributes_delete', label: 'Excluir atributos' },
        ],
      },
      {
        key: 'automation',
        label: 'Automação',
        icon: 'i-lucide-repeat',
        permissions: [
          { key: 'automation_view', label: 'Visualizar automações' },
          { key: 'automation_create', label: 'Criar automações' },
          { key: 'automation_edit', label: 'Editar automações' },
          { key: 'automation_delete', label: 'Excluir automações' },
        ],
      },
      {
        key: 'agent_bots',
        label: 'Robôs',
        icon: 'i-lucide-bot',
        permissions: [
          { key: 'agent_bots_view', label: 'Visualizar robôs' },
          { key: 'agent_bots_manage', label: 'Conectar e gerenciar robôs' },
        ],
      },
      {
        key: 'macros',
        label: 'Macros',
        icon: 'i-lucide-toy-brick',
        permissions: [
          { key: 'macros_view', label: 'Visualizar macros' },
          { key: 'macros_create', label: 'Criar macros' },
          { key: 'macros_edit', label: 'Editar macros' },
          { key: 'macros_delete', label: 'Excluir macros' },
        ],
      },
      {
        key: 'canned',
        label: 'Respostas prontas',
        icon: 'i-lucide-message-square-quote',
        permissions: [
          { key: 'canned_view', label: 'Visualizar respostas prontas' },
          { key: 'canned_create', label: 'Criar respostas prontas' },
          { key: 'canned_edit', label: 'Editar respostas prontas' },
          { key: 'canned_delete', label: 'Excluir respostas prontas' },
        ],
      },
      {
        key: 'integrations',
        label: 'Integrações',
        icon: 'i-lucide-blocks',
        permissions: [
          { key: 'integrations_view', label: 'Visualizar integrações' },
          { key: 'integrations_manage', label: 'Conectar e gerenciar integrações' },
        ],
      },
      {
        key: 'audit',
        label: 'Auditoria',
        icon: 'i-lucide-file-search',
        permissions: [
          { key: 'audit_view', label: 'Visualizar logs de auditoria' },
        ],
      },
      {
        key: 'roles',
        label: 'Funções personalizadas',
        icon: 'i-lucide-shield-plus',
        permissions: [
          { key: 'roles_view', label: 'Visualizar funções' },
          { key: 'roles_create', label: 'Criar funções' },
          { key: 'roles_edit', label: 'Editar funções' },
          { key: 'roles_delete', label: 'Excluir funções' },
        ],
      },
      {
        key: 'sla',
        label: 'SLA',
        icon: 'i-lucide-clock-alert',
        permissions: [
          { key: 'sla_view', label: 'Visualizar SLAs' },
          { key: 'sla_create', label: 'Criar SLAs' },
          { key: 'sla_edit', label: 'Editar SLAs' },
          { key: 'sla_delete', label: 'Excluir SLAs' },
        ],
      },
      {
        key: 'workflow',
        label: 'Fluxo de conversa',
        icon: 'i-lucide-workflow',
        permissions: [
          { key: 'workflow_view', label: 'Visualizar fluxos' },
          { key: 'workflow_manage', label: 'Gerenciar fluxos' },
        ],
      },
      {
        key: 'security',
        label: 'Segurança',
        icon: 'i-lucide-shield',
        permissions: [
          { key: 'security_view', label: 'Visualizar configurações de segurança' },
          { key: 'security_manage', label: 'Editar configurações de segurança' },
        ],
      },
      {
        key: 'billing',
        label: 'Cobrança',
        icon: 'i-lucide-credit-card',
        permissions: [
          { key: 'billing_view', label: 'Visualizar faturamento' },
          { key: 'billing_manage', label: 'Gerenciar faturamento' },
        ],
      },
    ],
  },
  {
    key: 'help',
    label: 'Ajuda',
    icon: 'i-lucide-life-buoy',
    description: 'Acesso ao centro de ajuda do Klivy.',
    permissions: [{ key: 'view', label: 'Acessar ajuda' }],
  },
];

export const MODULE_KEYS = MODULES.map(m => m.key);

export const moduleByKey = key => MODULES.find(m => m.key === key);

/**
 * Retorna `true` se o módulo usa o esquema agrupado.
 */
export const moduleHasGroups = mod =>
  Array.isArray(mod?.groups) && mod.groups.length > 0;

/**
 * Achata as permissões de um módulo (independente do esquema). Retorna a
 * lista de objetos `Permission`.
 */
export const flattenPermissions = mod => {
  if (!mod) return [];
  if (moduleHasGroups(mod)) {
    return mod.groups.flatMap(g => g.permissions || []);
  }
  return mod.permissions || [];
};

/**
 * Lista as permissões de um grupo específico dentro de um módulo agrupado.
 */
export const groupPermissions = (mod, groupKey) => {
  if (!moduleHasGroups(mod)) return [];
  const grp = mod.groups.find(g => g.key === groupKey);
  return grp?.permissions || [];
};

/**
 * Migrações de chaves legadas (esquema antigo flat → novo esquema agrupado).
 * Quando uma chave antiga estava `true`, todas as chaves novas correspondentes
 * recebem `true`. Roda dentro de `normalizePermissions` antes do filtro pelo
 * catálogo atual.
 */
const LEGACY_KEY_MIGRATIONS = {
  settings: {
    manage_users: ['users_view', 'users_invite', 'users_edit', 'users_remove'],
    manage_roles: ['roles_view', 'roles_create', 'roles_edit', 'roles_delete'],
    manage_inboxes: [
      'inboxes_view',
      'inboxes_create',
      'inboxes_edit',
      'inboxes_delete',
      'inboxes_manage_agents',
    ],
    manage_integrations: [
      'integrations_view',
      'integrations_manage',
      'agent_bots_view',
      'agent_bots_manage',
    ],
    manage_automation: [
      'automation_view',
      'automation_create',
      'automation_edit',
      'automation_delete',
      'workflow_view',
      'workflow_manage',
    ],
    manage_canned: [
      'canned_view',
      'canned_create',
      'canned_edit',
      'canned_delete',
    ],
    manage_labels: [
      'labels_view',
      'labels_create',
      'labels_edit',
      'labels_delete',
    ],
    manage_macros: [
      'macros_view',
      'macros_create',
      'macros_edit',
      'macros_delete',
    ],
    manage_billing: [
      'billing_view',
      'billing_manage',
      'account_view',
      'account_manage',
      'security_view',
      'security_manage',
    ],
    view_audit: ['audit_view'],
  },
};

/**
 * Constrói um hash de permissões zerado: cada módulo com cada permissão = false.
 */
export function emptyPermissionsHash() {
  return MODULES.reduce((acc, mod) => {
    acc[mod.key] = flattenPermissions(mod).reduce((modAcc, p) => {
      modAcc[p.key] = false;
      return modAcc;
    }, {});
    return acc;
  }, {});
}

/**
 * Garante que o hash de permissões tem todos os módulos do catálogo,
 * preenchendo com false os que faltarem (compat retroativa). Aplica
 * `LEGACY_KEY_MIGRATIONS` para preservar permissões salvas no esquema antigo.
 */
export function normalizePermissions(input = {}) {
  const empty = emptyPermissionsHash();
  return MODULES.reduce((acc, mod) => {
    const existing = input[mod.key] || {};
    const migrations = LEGACY_KEY_MIGRATIONS[mod.key] || {};
    acc[mod.key] = flattenPermissions(mod).reduce((modAcc, p) => {
      let value = existing[p.key] === true;
      if (!value) {
        // verifica se alguma chave legada que mapeia pra essa nova estava ativa
        for (const [legacyKey, mappedKeys] of Object.entries(migrations)) {
          if (existing[legacyKey] === true && mappedKeys.includes(p.key)) {
            value = true;
            break;
          }
        }
      }
      modAcc[p.key] = value;
      return modAcc;
    }, {});
    return acc;
  }, empty);
}

/**
 * Conta quantas permissões estão ativas no hash inteiro.
 */
export function countActivePermissions(perms = {}) {
  return MODULES.reduce((total, mod) => {
    const modPerms = perms[mod.key] || {};
    return (
      total +
      flattenPermissions(mod).filter(p => modPerms[p.key] === true).length
    );
  }, 0);
}

/**
 * Conta sub-permissões ativas em um módulo específico.
 */
export function countActiveInModule(perms, moduleKey) {
  const mod = moduleByKey(moduleKey);
  if (!mod) return 0;
  const modPerms = perms?.[moduleKey] || {};
  return flattenPermissions(mod).filter(p => modPerms[p.key] === true).length;
}

/**
 * Conta permissões ativas em um grupo específico de um módulo agrupado.
 */
export function countActiveInGroup(perms, moduleKey, groupKey) {
  const mod = moduleByKey(moduleKey);
  if (!mod || !moduleHasGroups(mod)) return 0;
  const modPerms = perms?.[moduleKey] || {};
  return groupPermissions(mod, groupKey).filter(
    p => modPerms[p.key] === true
  ).length;
}

/**
 * Retorna true se o módulo está totalmente desligado (toggle pai = off).
 */
export function isModuleDisabled(perms, moduleKey) {
  return countActiveInModule(perms, moduleKey) === 0;
}
