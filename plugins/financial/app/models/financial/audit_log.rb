module Financial
  # Registro automático de toda escrita em entidade financeira.
  # Canon Parte 6 + F-02. Inserção async para não bloquear transação principal.
  #
  # Auditoria não se auto-audita (audit_disabled = true).
  class AuditLog < ::ApplicationRecord
    self.table_name = 'financial_audit_logs'

    self.inheritance_column = :_type_disabled

    belongs_to :account, class_name: '::Account'
    belongs_to :user,    class_name: '::User', optional: true

    validates :entity_type, :entity_id, :action, presence: true

    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :for_entity, ->(record) {
      where(entity_type: record.class.name, entity_id: record.id)
    }
    scope :recent_first, -> { order(created_at: :desc) }

    # Async — usa job se disponível, senão grava direto.
    def self.async_record(record, action:, before:, after:)
      account_id = record.try(:account_id) || Financial::CurrentUser.account_id
      return if account_id.blank?

      payload = {
        account_id: account_id,
        user_id: Financial::CurrentUser.id,
        entity_type: record.class.name,
        entity_id: record.id,
        action: action.to_s,
        ip_address: Financial::CurrentUser.ip,
        user_agent: Financial::CurrentUser.user_agent&.first(500),
        before: scrub(before),
        after: scrub(after),
        metadata: build_metadata,
        created_at: Time.current
      }

      if defined?(Financial::AuditLogJob) && job_queue_available?
        Financial::AuditLogJob.perform_later(payload)
      else
        # fallback síncrono — depois do commit, mas sem job
        create!(payload)
      end
    rescue StandardError => e
      Rails.logger.error("[Financial::AuditLog] failed to record: #{e.class} #{e.message}")
    end

    def self.scrub(hash)
      return {} if hash.blank?

      hash.deep_stringify_keys.reject do |k, _|
        k.to_s.match?(/password|secret|api_key|token|ciphertext/i)
      end
    end

    def self.build_metadata
      meta = {}
      idem_key = Thread.current[:financial_idempotency_key]
      meta[:idempotency_key] = idem_key if idem_key
      meta
    end

    def self.job_queue_available?
      ActiveJob::Base.queue_adapter_name.present?
    rescue StandardError
      false
    end

    # AuditLog NÃO se audita (evita recursão infinita).
    def self.audit_disabled
      true
    end
  end
end
