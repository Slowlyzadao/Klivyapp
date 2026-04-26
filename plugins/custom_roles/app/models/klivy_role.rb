class KlivyRole < ApplicationRecord
  self.table_name = 'klivy_roles'

  belongs_to :account
  has_many :account_users, dependent: :nullify

  validates :name, presence: true, length: { maximum: 80 },
                   uniqueness: { scope: :account_id, case_sensitive: false }
  validates :description, length: { maximum: 240 }, allow_blank: true

  before_validation { self.permissions ||= {} }

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
end
