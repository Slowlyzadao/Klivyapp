module Financial
  module Concerns
    # Audit log automático: cada CREATE/UPDATE/DELETE/RESTORE em modelo financeiro
    # gera um Financial::AuditLog com before/after JSONB.
    # Canon: Parte 6 §"Soft delete + audit log" + BUG-12 + F-02.
    #
    # Modelos podem desabilitar via `self.audit_disabled = true`.
    # Inserção do log é após o commit para não bloquear a transação principal.
    module Auditable
      extend ActiveSupport::Concern

      AUDITED_ACTIONS = %i[create update destroy restore].freeze

      included do
        class_attribute :audit_disabled, default: false
        class_attribute :audit_excluded_columns, default: %w[
          created_at updated_at lock_version
          gateway_metadata gateway_synced_at
        ]

        # capturar estado antes da mudança para diff no after_commit
        before_save    :capture_audit_before_state, unless: :audit_disabled
        after_commit   :record_audit_create,  on: :create,  unless: :audit_disabled
        after_commit   :record_audit_update,  on: :update,  unless: :audit_disabled
        after_commit   :record_audit_destroy, on: :destroy, unless: :audit_disabled
      end

      private

      def capture_audit_before_state
        @audit_before_state = changes.transform_values(&:first).reject do |k, _|
          self.class.audit_excluded_columns.include?(k.to_s)
        end
      end

      def record_audit_create
        Financial::AuditLog.async_record(
          self,
          action: 'create',
          before: {},
          after: audit_serialize(self)
        )
      end

      def record_audit_update
        before = @audit_before_state || {}
        return if before.empty?

        after = before.keys.each_with_object({}) do |key, h|
          h[key] = self[key]
        end

        Financial::AuditLog.async_record(
          self,
          action: soft_delete_update? ? 'destroy' : (soft_restore_update? ? 'restore' : 'update'),
          before: before,
          after: after
        )
      end

      def record_audit_destroy
        Financial::AuditLog.async_record(
          self,
          action: 'destroy',
          before: audit_serialize(self),
          after: {}
        )
      end

      def soft_delete_update?
        return false unless respond_to?(:deleted_at)

        before = @audit_before_state || {}
        before.key?('deleted_at') && before['deleted_at'].nil? && deleted_at.present?
      end

      def soft_restore_update?
        return false unless respond_to?(:deleted_at)

        before = @audit_before_state || {}
        before.key?('deleted_at') && before['deleted_at'].present? && deleted_at.nil?
      end

      def audit_serialize(record)
        record.attributes.reject do |k, _|
          self.class.audit_excluded_columns.include?(k.to_s)
        end
      end
    end
  end
end
