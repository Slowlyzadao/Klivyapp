# app/models/concerns/beclinic_permissible.rb
#
# Concern incluído no User para fornecer métodos de verificação de permissões RBAC.
# As permissões vêm da KlivyRole atribuída ao account_user (plugins/custom_roles).
#
# Precedência (3 passos):
#   1. SuperAdmin (BeClinic — User#type) -> bypass total
#   2. Chatwoot administrator (account_user.role) -> bypass total
#   3. KlivyRole atribuída ao account_user -> consulta permissões; sem role -> false
#
module BeclinicPermissible
  extend ActiveSupport::Concern

  # Returns the KlivyRole assigned to this user via account_users.klivy_role_id.
  def klivy_role_for(account)
    au = account_users.find_by(account_id: account.id)
    au&.klivy_role
  end

  # Returns true if the user is a Chatwoot administrator in the given account.
  def beclinic_admin_in?(account)
    au = account_users.find_by(account_id: account.id)
    au&.administrator? || false
  end

  # Primary permission check method.
  # @param account [Account]
  # @param module_name [Symbol] e.g. :patients, :agenda, :financial
  # @param action [Symbol] e.g. :view, :create, :delete
  def beclinic_can?(account, module_name, action)
    return true if beclinic_super_admin?
    return true if beclinic_admin_in?(account)

    klivy_role = klivy_role_for(account)
    klivy_role ? klivy_role.can?(module_name, action) : false
  end

  # Returns the scope ('all' or 'own') for a given module.
  # Admins always get 'all'. Without role, defaults to 'own' (most restrictive).
  def beclinic_scope(account, module_name)
    return 'all' if beclinic_super_admin?
    return 'all' if beclinic_admin_in?(account)

    klivy_role = klivy_role_for(account)
    klivy_role ? klivy_role.scope_for(module_name) : 'own'
  end

  # Returns a label describing the user's role in the account.
  def beclinic_role_for(account)
    return 'super_admin' if beclinic_super_admin?
    return 'administrator' if beclinic_admin_in?(account)

    klivy_role_for(account)&.name
  end

  # Returns the permissions hash for the user in the account.
  #
  # Para admin/SuperAdmin retorna `{}` — o frontend faz bypass total via
  # `usePermissions#isAdmin` (que checa `getCurrentRole === 'administrator'`
  # ANTES de consultar o store) e o backend faz bypass via `beclinic_can?`
  # (que retorna true antes de checar permissions). Logo o payload pra admin
  # não é consultado em lugar nenhum — retornar um hash hardcoded só servia
  # pra ficar dessincronizado com o catálogo real (auditoria M-9: o hash
  # antigo tinha keys defasadas — `chat.transfer_inbox`, `financial.view_transactions`,
  # `settings.manage_users`, `agenda.scope` symbol, etc.).
  def beclinic_permissions_for(account)
    return {} if beclinic_super_admin?
    return {} if beclinic_admin_in?(account)

    klivy_role_for(account)&.permissions || {}
  end

  # Super admin check — true if the user's type is SuperAdmin (BeClinic owners).
  # These users have full bypass on all permission checks.
  def beclinic_super_admin?
    is_a?(SuperAdmin)
  end
end
