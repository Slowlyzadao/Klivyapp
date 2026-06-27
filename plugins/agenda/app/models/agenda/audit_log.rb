module Agenda
  # Registro automático de toda escrita em entidade da agenda.
  # PR #8 da auditoria 2026-05-13 — espelha `Financial::AuditLog` (canon F-02).
  #
  # Inserção async via `Agenda::AuditLogJob` para não bloquear a transação
  # do save da entidade auditada. Fallback síncrono se job queue não estiver
  # disponível (specs, console, seeds).
  #
  # Imutável: bloqueia update e destroy por design.
  class AuditLog < ::ApplicationRecord
    self.table_name = 'agenda_audit_logs'
    self.inheritance_column = :_type_disabled

    belongs_to :account, class_name: '::Account'
    belongs_to :user,    class_name: '::User', optional: true

    validates :entity_type, :entity_id, :action, presence: true

    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :for_entity, ->(record) {
      where(entity_type: record.class.name, entity_id: record.id)
    }
    scope :recent_first, -> { order(created_at: :desc) }

    # Log é imutável por compliance — bloqueia update e destroy no nível Ruby.
    # (FK e índices não impedem; isso é defesa adicional.)
    before_update { raise FrozenError, 'Agenda::AuditLog is immutable — cannot be updated' }
    before_destroy { raise FrozenError, 'Agenda::AuditLog is immutable — cannot be destroyed' }

    # Campos sensíveis que NUNCA devem vazar no JSONB. Convenção alinhada com
    # PatientAuditLog: senhas, tokens, secrets jamais em texto plano.
    SENSITIVE_KEY_PATTERN = /password|secret|api_key|token|ciphertext|access_token/i

    # API pública: chamada pelo concern `Agenda::Concerns::Auditable` após
    # cada commit. Não falha o save da entidade auditada — engole erros e loga.
    def self.async_record(record, action:, before: nil, after: nil)
      account_id = record.try(:account_id) || current_account_id
      return if account_id.blank?

      payload = build_payload(record, account_id, action, before, after)

      if defined?(Agenda::AuditLogJob) && job_queue_available?
        Agenda::AuditLogJob.perform_later(payload)
      else
        # Fallback síncrono — usado em specs/console onde queue não está ativa.
        create!(payload)
      end
    rescue StandardError => e
      Rails.logger.error("[Agenda::AuditLog] failed to record: #{e.class} #{e.message}")
    end

    # Scrub: redige valores de chaves sensíveis preservando a forma do hash.
    # `[REDACTED]` substitui o conteúdo; tipos array (diff `[old, new]`) ficam
    # `[[REDACTED], [REDACTED]]`.
    def self.scrub(hash)
      return {} if hash.blank?

      hash.deep_stringify_keys.each_with_object({}) do |(key, value), result|
        result[key] =
          if key.to_s.match?(SENSITIVE_KEY_PATTERN)
            value.is_a?(Array) ? value.map { '[REDACTED]' } : '[REDACTED]'
          else
            value
          end
      end
    end

    def self.build_payload(record, account_id, action, before, after)
      {
        account_id: account_id,
        user_id: current_user_id,
        entity_type: record.class.name,
        entity_id: record.id,
        action: action.to_s,
        ip_address: current_ip,
        user_agent: current_user_agent&.first(500),
        # JSON-roundtrip normaliza tipos não-serializáveis pelo ActiveJob:
        # BigDecimal → string, Time → ISO 8601, etc. Sem isso, snapshots de
        # create (`attributes` completo) explodem com SerializationError em
        # apps Rails <7.1 (ou com `use_big_decimal_serializer = false`),
        # e o rescue do `async_record` engolia o erro silenciosamente.
        # Update/archive escapavam por azar — o diff não incluía BigDecimal.
        before: json_safe(scrub(before)),
        after: json_safe(scrub(after)),
        metadata: {},
        created_at: Time.current
      }
    end
    private_class_method :build_payload

    def self.json_safe(hash)
      return {} if hash.blank?

      JSON.parse(hash.to_json)
    rescue StandardError => e
      Rails.logger.warn("[Agenda::AuditLog] json_safe fallback: #{e.class} #{e.message}")
      {}
    end
    private_class_method :json_safe

    # Wrappers tolerantes ao Current não estar configurado (jobs, console, seeds).
    def self.current_account_id
      return nil unless defined?(::Current)

      ::Current.account&.id
    rescue NoMethodError
      nil
    end
    private_class_method :current_account_id

    def self.current_user_id
      return nil unless defined?(::Current)

      ::Current.user&.id
    rescue NoMethodError
      nil
    end
    private_class_method :current_user_id

    def self.current_ip
      return nil unless defined?(::Current)

      ::Current.try(:request_ip) || ::Current.try(:ip)
    rescue NoMethodError
      nil
    end
    private_class_method :current_ip

    def self.current_user_agent
      return nil unless defined?(::Current)

      ::Current.try(:user_agent)
    rescue NoMethodError
      nil
    end
    private_class_method :current_user_agent

    def self.job_queue_available?
      ActiveJob::Base.queue_adapter_name.present?
    rescue StandardError
      false
    end
    private_class_method :job_queue_available?
  end
end
