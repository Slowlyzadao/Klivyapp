module BeclinicCore
  class TeamProfile < ApplicationRecord
    self.table_name = 'beclinic_team_profiles'
    belongs_to :team

    BECLINIC_ROLES = %w[dono gerente especialista].freeze

    PRESET_PERMISSIONS = {
      'recepcionista' => {
        beclinic_role: 'gerente',
        patients: { scope: 'all', view: true, create: true, edit: true, delete: false,
                    view_clinical_notes: false, create_clinical_notes: false, sign_clinical_notes: false,
                    delete_clinical_notes: false, view_treatment_plans: true, manage_treatment_plans: false,
                    view_consents: true, manage_consents: false, view_documents: true, manage_documents: false,
                    view_exams: true, manage_exams: false, view_audit: false, view_timeline: true },
        agenda: { scope: 'all', view: true, create_event: true, edit_event: true, cancel_event: true,
                  drag_and_drop: true, manage_blocks: false, view_notifications: true, manage_notifications: false },
        financial: { view_transactions: true, create_transaction: true, delete_transaction: false,
                     view_estimates: true, create_estimate: false, edit_estimate: false,
                     approve_estimate: false, delete_estimate: false, view_cashflow: false, export_cashflow: false },
        chat: { view_all: true, view_unassigned: true, reply: true, assign_conversation: true,
                transfer_inbox: true, delete_message: false, send_broadcast: false },
        settings: { manage_users: false, manage_roles: false, manage_agenda_config: false,
                    manage_inboxes: false, view_reports: false }
      },
      'especialista' => {
        beclinic_role: 'especialista',
        patients: { scope: 'own', view: true, create: true, edit: true, delete: false,
                    view_clinical_notes: true, create_clinical_notes: true, sign_clinical_notes: true,
                    delete_clinical_notes: true, view_treatment_plans: true, manage_treatment_plans: true,
                    view_consents: true, manage_consents: true, view_documents: true, manage_documents: true,
                    view_exams: true, manage_exams: true, view_audit: true, view_timeline: true },
        agenda: { scope: 'own', view: true, create_event: true, edit_event: true, cancel_event: true,
                  drag_and_drop: true, manage_blocks: true, view_notifications: true, manage_notifications: false },
        financial: { view_transactions: true, create_transaction: true, delete_transaction: false,
                     view_estimates: true, create_estimate: true, edit_estimate: true,
                     approve_estimate: false, delete_estimate: false, view_cashflow: false, export_cashflow: false },
        chat: { view_all: false, view_unassigned: false, reply: true, assign_conversation: false,
                transfer_inbox: false, delete_message: false, send_broadcast: false },
        settings: { manage_users: false, manage_roles: false, manage_agenda_config: false,
                    manage_inboxes: false, view_reports: false }
      },
      'gerente' => {
        beclinic_role: 'gerente',
        patients: { scope: 'all', view: true, create: true, edit: true, delete: true,
                    view_clinical_notes: true, create_clinical_notes: true, sign_clinical_notes: true,
                    delete_clinical_notes: true, view_treatment_plans: true, manage_treatment_plans: true,
                    view_consents: true, manage_consents: true, view_documents: true, manage_documents: true,
                    view_exams: true, manage_exams: true, view_audit: true, view_timeline: true },
        agenda: { scope: 'all', view: true, create_event: true, edit_event: true, cancel_event: true,
                  drag_and_drop: true, manage_blocks: true, view_notifications: true, manage_notifications: true },
        financial: { view_transactions: true, create_transaction: true, delete_transaction: true,
                     view_estimates: true, create_estimate: true, edit_estimate: true,
                     approve_estimate: true, delete_estimate: true, view_cashflow: true, export_cashflow: true },
        chat: { view_all: true, view_unassigned: true, reply: true, assign_conversation: true,
                transfer_inbox: true, delete_message: true, send_broadcast: true },
        settings: { manage_users: true, manage_roles: true, manage_agenda_config: true,
                    manage_inboxes: false, view_reports: true }
      },
      'sdr' => {
        beclinic_role: 'especialista',
        patients: { scope: 'all', view: true, create: true, edit: false, delete: false,
                    view_clinical_notes: false, create_clinical_notes: false, sign_clinical_notes: false,
                    delete_clinical_notes: false, view_treatment_plans: false, manage_treatment_plans: false,
                    view_consents: false, manage_consents: false, view_documents: false, manage_documents: false,
                    view_exams: false, manage_exams: false, view_audit: false, view_timeline: true },
        agenda: { scope: 'all', view: true, create_event: true, edit_event: true, cancel_event: true,
                  drag_and_drop: false, manage_blocks: false, view_notifications: false, manage_notifications: false },
        financial: { view_transactions: false, create_transaction: false, delete_transaction: false,
                     view_estimates: true, create_estimate: true, edit_estimate: true,
                     approve_estimate: false, delete_estimate: false, view_cashflow: false, export_cashflow: false },
        chat: { view_all: true, view_unassigned: true, reply: true, assign_conversation: true,
                transfer_inbox: false, delete_message: false, send_broadcast: true },
        settings: { manage_users: false, manage_roles: false, manage_agenda_config: false,
                    manage_inboxes: false, view_reports: false }
      }
    }.freeze

    validates :beclinic_role, inclusion: { in: BECLINIC_ROLES }, allow_nil: true

    before_validation do
      self.permissions ||= {}
    end

    def can?(module_name, action)
      perms = permissions.deep_symbolize_keys
      perms.dig(module_name.to_sym, action.to_sym) == true
    end

    def scope_for(module_name)
      perms = permissions.deep_symbolize_keys
      perms.dig(module_name.to_sym, :scope) || 'all'
    end

    def dono?
      beclinic_role == 'dono'
    end
  end
end
