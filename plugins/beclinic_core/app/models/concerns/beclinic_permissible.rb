# app/models/concerns/beclinic_permissible.rb
#
# Concern incluído no User para fornecer métodos de verificação de permissões RBAC.
# As permissões são lidas a partir do primeiro Time (Team) do usuário na conta atual.
# O `administrator` nativo (super admin BeClinic) tem bypass total em tudo.
#
module BeclinicPermissible
  extend ActiveSupport::Concern

  # Returns the user's RBAC team for the given account.
  # Uses the first team the user belongs to in that account.
  def beclinic_team_for(account)
    teams.joins(:team_members)
         .where(account_id: account.id)
         .first
  end

  # Primary permission check method.
  # Administrators (super admins) bypass all checks.
  # Dono-role teams also have full access.
  # @param account [Account]
  # @param module_name [Symbol] e.g. :patients, :agenda, :financial
  # @param action [Symbol] e.g. :view, :create, :delete
  def beclinic_can?(account, module_name, action)
    return true if beclinic_super_admin?

    team = beclinic_team_for(account)
    return true if team&.dono?
    return false unless team

    team.can?(module_name, action)
  end

  # Returns the scope ('all' or 'own') for a given module.
  # Admins and dono teams always get 'all'.
  def beclinic_scope(account, module_name)
    return 'all' if beclinic_super_admin?

    team = beclinic_team_for(account)
    return 'all' if team&.dono?
    return 'own' unless team

    team.scope_for(module_name)
  end

  # Returns the beclinic_role string from the user's team.
  def beclinic_role_for(account)
    return 'super_admin' if beclinic_super_admin?

    team = beclinic_team_for(account)
    team&.beclinic_role || 'especialista'
  end

  # Returns all permissions hash for the user's team.
  def beclinic_permissions_for(account)
    return full_permissions_hash if beclinic_super_admin?

    team = beclinic_team_for(account)
    return full_permissions_hash if team&.dono?

    team&.permissions || {}
  end

  # Super admin check — true if the user's type is SuperAdmin (BeClinic owners).
  # These users have full bypass on all permission checks.
  def beclinic_super_admin?
    is_a?(SuperAdmin)
  end

  private

  def full_permissions_hash
    {
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
                  manage_inboxes: true, view_reports: true }
    }
  end
end
