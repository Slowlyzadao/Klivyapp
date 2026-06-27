module Financial
  module Concerns
    # Audit log automático: cada CREATE/UPDATE/DELETE/RESTORE em modelo financeiro
    # gera um Financial::AuditLog com before/after JSONB.
    # Canon: Parte 6 §"Soft delete + audit log" + BUG-12 + F-02.
    #
    # Modelos podem desabilitar via `self.audit_disabled = true`.
    # Inserção do log é após o commit para não bloquear a transação principal.
    #
    # Também expõe `frozen_attributes` para imutabilidade declarativa
    # (canon Parte 6 §"Imutabilidade primeiro"):
    #
    #   class Financial::Installment < Financial::ApplicationRecord
    #     frozen_attributes :amount_cents, :payment_method_fee_id,
    #                       :fee_percent_basis_points, :mdr_deduction_cents
    #   end
    #
    # `frozen_attributes` faz duas coisas:
    #   1. `attr_readonly` (Rails — bloqueia em UPDATE via AR normal)
    #   2. Validação `if persisted? && X_changed?` (defense in depth contra
    #      `assign_attributes` + `save(validate: false)` ou cases raros)
    #
    # NÃO bloqueia `update_columns` (que é SQL direto) — pra esses casos,
    # a auditoria registra a mudança e o usuário fica com trilha.
    module Auditable
      extend ActiveSupport::Concern

      AUDITED_ACTIONS = %i[create update destroy restore].freeze

      included do
        class_attribute :audit_disabled, default: false
        class_attribute :audit_excluded_columns, default: %w[
          created_at updated_at lock_version
          gateway_metadata gateway_synced_at
        ]

        # Lista de colunas imutáveis após criação. Populada via `frozen_attributes`.
        class_attribute :_frozen_attributes, default: []

        # capturar estado antes da mudança para diff no after_commit
        before_save    :capture_audit_before_state, unless: :audit_disabled
        after_commit   :record_audit_create,  on: :create,  unless: :audit_disabled
        after_commit   :record_audit_update,  on: :update,  unless: :audit_disabled
        after_commit   :record_audit_destroy, on: :destroy, unless: :audit_disabled

        # Validação de imutabilidade — só em UPDATE.
        validate :frozen_attributes_not_changed, on: :update
      end

      class_methods do
        # Declara colunas imutáveis após criação. Combina `attr_readonly` (que
        # Rails honra em assign_attributes via AR público) com validação
        # explícita que detecta `model.foo = X` direto (`_changed?`).
        #
        #   frozen_attributes :amount_cents, :payment_method_fee_id
        #
        # Soft-delete (`deleted_at`, `deleted_by_id`) e timestamps de auditoria
        # (`updated_by_id`, `updated_at`) NÃO devem entrar em `frozen_attributes`
        # — soft delete é update legítimo.
        def frozen_attributes(*attrs)
          attrs = attrs.flatten.map(&:to_s)
          self._frozen_attributes = (_frozen_attributes + attrs).uniq
          attr_readonly(*attrs)
        end
      end

      private

      def frozen_attributes_not_changed
        self.class._frozen_attributes.each do |attr|
          # Só valida em UPDATE (persisted? + _changed?). `attr_readonly` já
          # bloqueia mass assignment via AR público; isto pega bypass via setter.
          next unless respond_to?("#{attr}_changed?")
          next unless public_send("#{attr}_changed?")

          errors.add(attr.to_sym, 'é imutável após criação (snapshot histórico)')
        end
      end

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
