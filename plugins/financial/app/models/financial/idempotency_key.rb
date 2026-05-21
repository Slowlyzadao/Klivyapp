module Financial
  # Chave de idempotência server-side. Canon Parte 6 §"Idempotência".
  # TTL 24h. Limpeza periódica via job (Financial::IdempotencyKeyCleanupJob).
  class IdempotencyKey < ::ApplicationRecord
    self.table_name = 'financial_idempotency_keys'
    self.inheritance_column = :_type_disabled
    self.audit_disabled = true if respond_to?(:audit_disabled=)

    TTL = 24.hours

    belongs_to :account, class_name: '::Account'
    belongs_to :user, class_name: '::User', optional: true

    validates :key, :request_path, :request_method, :request_fingerprint, :response_status, presence: true

    scope :fresh,  -> { where('created_at > ?', TTL.ago) }
    scope :stale,  -> { where('created_at <= ?', TTL.ago) }

    def fresh?
      created_at > TTL.ago
    end

    def matches_request?(path, method, fingerprint)
      request_path == path &&
        request_method.to_s.upcase == method.to_s.upcase &&
        request_fingerprint == fingerprint
    end
  end
end
