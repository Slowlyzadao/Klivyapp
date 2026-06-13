module Financial
  # Cada webhook recebido é registrado para auditoria e reprocessamento.
  # Idempotência: (gateway, event_id) é UNIQUE → entregas duplicadas viram no-op.
  class GatewayWebhookEvent < ::ApplicationRecord
    self.table_name = 'financial_gateway_webhook_events'
    self.inheritance_column = :_type_disabled

    STATUSES = %w[received processed failed ignored].freeze

    belongs_to :account, class_name: '::Account'

    validates :gateway, :event_id, :event_type, :status, :payload, :received_at, presence: true
    validates :event_id, uniqueness: { scope: :gateway }

    scope :pending, -> { where(status: 'received') }
    scope :failed,  -> { where(status: 'failed') }

    def mark_processed!
      update!(status: 'processed', processed_at: Time.current)
    end

    def mark_failed!(error)
      update!(
        status: 'failed',
        processing_error: error.message,
        processing_attempts: processing_attempts + 1
      )
    end

    def mark_ignored!(reason = nil)
      update!(status: 'ignored', processing_error: reason)
    end
  end
end
