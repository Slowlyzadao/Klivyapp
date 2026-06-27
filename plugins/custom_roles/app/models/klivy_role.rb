class KlivyRole < ApplicationRecord
  self.table_name = 'klivy_roles'

  belongs_to :account
  has_many :account_users, dependent: :nullify

  validates :name, presence: true, length: { maximum: 80 },
                   uniqueness: { scope: :account_id, case_sensitive: false }
  validates :description, length: { maximum: 240 }, allow_blank: true

  before_validation { self.permissions ||= {} }
  # Sanitiza/migra `permissions` ANTES de validar/salvar (auditoria C-2).
  # Garante que o JSONB sempre esteja em forma canônica, descartando keys
  # arbitrárias do payload e migrando keys legadas (`settings.manage_users` →
  # `users_view/_invite/_edit/_remove` etc.). Ver `KlivyRole::PermissionsCatalog`.
  # Idempotente — rodar de novo em hash já sanitizado retorna o mesmo hash.
  before_validation :sanitize_permissions

  def can?(module_name, action)
    perms = permissions.deep_symbolize_keys
    perms.dig(module_name.to_sym, action.to_sym) == true
  end

  def module_enabled?(module_name)
    perms = permissions.deep_symbolize_keys[module_name.to_sym]
    return false unless perms.is_a?(Hash)

    perms.except(:scope).any? { |_, v| v == true }
  end

  def scope_for(module_name)
    perms = permissions.deep_symbolize_keys
    perms.dig(module_name.to_sym, :scope) || 'all'
  end

  private

  def sanitize_permissions
    self.permissions = PermissionsCatalog.sanitize_and_migrate(permissions || {})
  end
end
