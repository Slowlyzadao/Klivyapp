module CustomRoles
  # Definições Ruby dos 4 presets do Klivy — espelho exato de
  # `plugins/custom_roles/frontend/shared/presets.js`. Usado por:
  #   - `PresetSeeder` (lote 10): cria/restaura presets em contas existentes.
  #   - `Account.after_create` hook: cria os 4 presets em contas novas.
  #
  # IMPORTANTE: manter em SYNC com `presets.js`. Se mudar lá, mudar aqui.
  # Idealmente futura iteração move pra um único arquivo .json fonte que
  # ambos consomem.
  module PresetDefinitions
    RECEPCIONISTA = {
      label: 'Recepcionista',
      preset_key: 'recepcionista',
      description: 'Agenda, cadastro e visualização. Sem acesso clínico profundo.',
      permissions: {
        'inbox' => { 'view' => true, 'mark_read' => true },
        'chat' => {
          'view_all' => true, 'view_unassigned' => true, 'view_mentions' => true,
          'reply' => true, 'assign_conversation' => true,
          'view_conversation_actions' => true, 'use_macros' => true,
          'view_conversation_info' => true, 'view_contact_attributes' => true,
          'view_contact_notes' => true, 'view_previous_conversations' => true,
          'view_participants' => true, 'edit_contact' => true,
          'manage_waiting_list' => true
        },
        'captain' => { 'view' => true },
        'agenda' => {
          'view' => true, 'create_event' => true, 'edit_event' => true,
          'cancel_event' => true, 'drag_and_drop' => true,
          'view_notifications' => true
        },
        'patients' => {
          'view' => true, 'create' => true, 'edit' => true,
          'view_treatment_plans' => true, 'view_consents' => true,
          'view_documents' => true, 'view_exams' => true, 'view_timeline' => true
        },
        'financial' => {
          'view_dashboard' => true, 'view_receivables' => true,
          'create_transaction' => true
        },
        'contacts' => {
          'view_all' => true, 'view_active' => true,
          'create' => true, 'edit' => true
        },
        'reports' => { 'view_overview' => true, 'view_agenda' => true },
        'campaigns' => { 'view' => true },
        'help_center' => { 'view' => true },
        'help' => { 'view' => true }
      }
    }.freeze

    ESPECIALISTA = {
      label: 'Especialista',
      preset_key: 'especialista',
      description: 'Acesso clínico completo. Foco em prontuário e atendimento.',
      permissions: {
        'inbox' => { 'view' => true, 'mark_read' => true },
        'chat' => {
          'view_mentions' => true, 'reply' => true,
          'view_conversation_actions' => true, 'use_macros' => true,
          'view_conversation_info' => true, 'view_contact_attributes' => true,
          'view_contact_notes' => true, 'view_previous_conversations' => true,
          'view_participants' => true, 'view_patient_record' => true,
          'edit_contact' => true, 'manage_waiting_list' => true,
          'view_contact_profile' => true
        },
        'captain' => { 'view' => true, 'use_playground' => true },
        'agenda' => {
          'is_provider' => true, 'view' => true,
          'create_event' => true, 'edit_event' => true, 'cancel_event' => true,
          'drag_and_drop' => true, 'manage_blocks' => true,
          'view_notifications' => true
        },
        'patients' => {
          'view' => true, 'create' => true, 'edit' => true,
          'view_anamnesis' => true, 'manage_anamnesis' => true,
          'view_clinical_notes' => true, 'create_clinical_notes' => true,
          'sign_clinical_notes' => true,
          'view_treatment_plans' => true, 'manage_treatment_plans' => true,
          'view_consents' => true, 'manage_consents' => true,
          'view_documents' => true, 'manage_documents' => true,
          'view_exams' => true, 'manage_exams' => true,
          'view_timeline' => true,
          'view_financial' => true, 'manage_financial' => true
        },
        'financial' => { 'view_dashboard' => true, 'manage_estimates' => true },
        'contacts' => { 'view_active' => true },
        'reports' => { 'view_agent' => true, 'view_agenda' => true },
        'help' => { 'view' => true }
      }
    }.freeze

    GERENTE = {
      label: 'Gerente',
      preset_key: 'gerente',
      description: 'Acesso total: clínico, financeiro, relatórios e configurações. Sem agenda própria por padrão.',
      permissions: {
        'inbox' => { 'view' => true, 'mark_read' => true },
        'chat' => {
          'view_all' => true, 'view_unassigned' => true, 'view_mentions' => true,
          'reply' => true, 'assign_conversation' => true,
          'delete_message' => true, 'send_broadcast' => true,
          'view_conversation_actions' => true, 'use_macros' => true,
          'view_conversation_info' => true, 'view_contact_attributes' => true,
          'view_contact_notes' => true, 'view_previous_conversations' => true,
          'view_participants' => true, 'view_patient_record' => true,
          'edit_contact' => true, 'merge_contact' => true,
          'manage_waiting_list' => true, 'view_contact_profile' => true,
          'delete_contact' => true
        },
        'captain' => {
          'view' => true, 'manage_faqs' => true, 'manage_documents' => true,
          'manage_scenarios' => true, 'use_playground' => true,
          'manage_inboxes' => true, 'manage_tools' => true,
          'manage_settings' => true
        },
        'agenda' => {
          'view' => true, 'create_event' => true, 'edit_event' => true,
          'cancel_event' => true, 'drag_and_drop' => true,
          'manage_blocks' => true, 'view_settings' => true,
          'manage_schedules' => true, 'manage_online_booking' => true,
          'manage_services' => true, 'view_notifications' => true,
          'manage_notifications' => true, 'manage_custom_attributes' => true
        },
        'patients' => {
          'view' => true, 'create' => true, 'edit' => true, 'delete' => true,
          'view_anamnesis' => true, 'manage_anamnesis' => true,
          'view_clinical_notes' => true, 'create_clinical_notes' => true,
          'sign_clinical_notes' => true, 'delete_clinical_notes' => true,
          'view_treatment_plans' => true, 'manage_treatment_plans' => true,
          'view_consents' => true, 'manage_consents' => true,
          'view_documents' => true, 'manage_documents' => true,
          'view_exams' => true, 'manage_exams' => true,
          'view_audit' => true, 'view_timeline' => true,
          'view_financial' => true, 'manage_financial' => true
        },
        'financial' => {
          'view_dashboard' => true, 'view_cashflow' => true,
          'view_receivables' => true, 'view_payables' => true,
          'view_dre' => true, 'view_reports' => true,
          'view_cash_register' => true, 'create_transaction' => true,
          'edit_transaction' => true, 'delete_transaction' => true,
          'manage_estimates' => true, 'approve_estimate' => true,
          'export_data' => true, 'manage_settings' => true
        },
        'contacts' => {
          'view_all' => true, 'view_active' => true,
          'create' => true, 'edit' => true, 'delete' => true,
          'manage_segments' => true, 'manage_tags' => true,
          'import_export' => true
        },
        'reports' => {
          'view_overview' => true, 'view_conversation' => true,
          'view_agent' => true, 'view_label' => true,
          'view_inbox' => true, 'view_team' => true,
          'view_csat' => true, 'view_sla' => true,
          'view_bot' => true, 'view_agenda' => true
        },
        'campaigns' => {
          'view' => true, 'manage_live_chat' => true,
          'manage_sms' => true, 'manage_whatsapp' => true
        },
        'help_center' => {
          'view' => true, 'manage_articles' => true,
          'manage_categories' => true, 'manage_portals' => true
        },
        'settings' => {
          'account_view' => true, 'account_manage' => true,
          'users_view' => true, 'users_invite' => true,
          'users_edit' => true, 'users_remove' => true,
          'teams_view' => true, 'teams_create' => true,
          'teams_edit' => true, 'teams_delete' => true,
          'inboxes_view' => true, 'inboxes_create' => true,
          'inboxes_edit' => true, 'inboxes_delete' => true,
          'inboxes_manage_agents' => true,
          'labels_view' => true, 'labels_create' => true,
          'labels_edit' => true, 'labels_delete' => true,
          'custom_attributes_view' => true, 'custom_attributes_create' => true,
          'custom_attributes_edit' => true, 'custom_attributes_delete' => true,
          'automation_view' => true, 'automation_create' => true,
          'automation_edit' => true, 'automation_delete' => true,
          'agent_bots_view' => true, 'agent_bots_manage' => true,
          'macros_view' => true, 'macros_create' => true,
          'macros_edit' => true, 'macros_delete' => true,
          'canned_view' => true, 'canned_create' => true,
          'canned_edit' => true, 'canned_delete' => true,
          'integrations_view' => true, 'integrations_manage' => true,
          'audit_view' => true,
          'roles_view' => true, 'roles_create' => true,
          'roles_edit' => true, 'roles_delete' => true,
          'sla_view' => true, 'sla_create' => true,
          'sla_edit' => true, 'sla_delete' => true,
          'workflow_view' => true, 'workflow_manage' => true,
          'security_view' => true, 'security_manage' => true,
          'billing_view' => true, 'billing_manage' => true
        },
        'help' => { 'view' => true }
      }
    }.freeze

    SDR = {
      label: 'SDR / Comercial',
      preset_key: 'sdr',
      description: 'Captação, orçamentos e agenda. Sem acesso ao prontuário.',
      permissions: {
        'inbox' => { 'view' => true, 'mark_read' => true },
        'chat' => {
          'view_all' => true, 'view_unassigned' => true, 'view_mentions' => true,
          'reply' => true, 'assign_conversation' => true,
          'send_broadcast' => true, 'view_conversation_actions' => true,
          'use_macros' => true, 'view_conversation_info' => true,
          'view_contact_attributes' => true, 'view_contact_notes' => true,
          'view_previous_conversations' => true, 'view_participants' => true,
          'edit_contact' => true, 'manage_waiting_list' => true,
          'view_contact_profile' => true
        },
        'captain' => { 'view' => true, 'use_playground' => true },
        'agenda' => {
          'view' => true, 'create_event' => true,
          'edit_event' => true, 'cancel_event' => true
        },
        'patients' => { 'view' => true, 'create' => true, 'view_timeline' => true },
        'financial' => { 'view_dashboard' => true, 'manage_estimates' => true },
        'contacts' => {
          'view_all' => true, 'view_active' => true,
          'create' => true, 'edit' => true,
          'manage_segments' => true, 'manage_tags' => true
        },
        'reports' => { 'view_overview' => true, 'view_agent' => true },
        'campaigns' => {
          'view' => true, 'manage_live_chat' => true,
          'manage_sms' => true, 'manage_whatsapp' => true
        },
        'help' => { 'view' => true }
      }
    }.freeze

    ALL = [RECEPCIONISTA, ESPECIALISTA, GERENTE, SDR].freeze
  end
end
