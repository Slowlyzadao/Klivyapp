module AiAgent
  class AuditLog < ApplicationRecord
    self.table_name = 'ai_agent_audit_logs'

    SCOPES = %w[global account persona tool].freeze

    validates :scope, inclusion: { in: SCOPES }
    validates :action, presence: true

    # Bea audit entries are append-only; clients should never edit them.
    def readonly?
      persisted?
    end

    def self.record(scope:, action:, actor: nil, account_id: nil, ip: nil, changes: {})
      attrs = {
        scope: scope,
        action: action,
        account_id: account_id,
        ip_address: ip,
        changes_summary: changes,
        created_at: Time.current
      }

      case actor
      when SuperAdmin then attrs[:super_admin_id] = actor.id
      when User then attrs[:user_id] = actor.id
      end

      create!(attrs)
    end
  end
end
