module Financial
  module Concerns
    # Soft delete com deleted_at + deleted_by_id (canon Parte 6).
    # Listagens default filtram registros vivos.
    module SoftDeletable
      extend ActiveSupport::Concern

      included do
        # `included` roda no `Financial::ApplicationRecord` (abstract) — checar
        # `column_names` aqui não funciona pois retorna []. Por isso o scope
        # é avaliado por subclasse em cada query (lambda olha column_names da
        # tabela real). Tabelas sem `deleted_at` (revenue_goals, audit_logs,
        # idempotency_keys, setup_states, gateway_settings) viram no-op.
        scope :alive,   -> { column_names.include?('deleted_at') ? where(deleted_at: nil) : all }
        scope :deleted, -> { column_names.include?('deleted_at') ? where.not(deleted_at: nil) : none }
        default_scope { column_names.include?('deleted_at') ? where(deleted_at: nil) : all }
      end

      class_methods do
        # Para listagens administrativas (ADMIN/AUDITOR) — view "Lixeira".
        def with_deleted
          unscope(where: :deleted_at)
        end

        def only_deleted
          with_deleted.deleted
        end
      end

      def soft_delete!(user: nil)
        return self if deleted?

        update_columns(
          deleted_at: Time.current,
          deleted_by_id: user&.id,
          updated_at: Time.current
        )
        self
      end

      def restore!(user: nil)
        return self unless deleted?

        update_columns(
          deleted_at: nil,
          deleted_by_id: nil,
          updated_by_id: user&.id,
          updated_at: Time.current
        )
        self
      end

      def deleted?
        deleted_at.present?
      end
    end
  end
end
