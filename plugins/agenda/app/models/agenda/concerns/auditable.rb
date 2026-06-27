module Agenda
  module Concerns
    # Aplica auditoria automática em qualquer model da agenda. Mesmo padrão
    # do Financial::* (canon Klivy F-02).
    #
    # Uso:
    #   class AgendaService < ApplicationRecord
    #     include Agenda::Concerns::Auditable
    #   end
    #
    # Captura:
    # - `create` → snapshot completo dos atributos em `after`
    # - `update` → diff (campo: [antigo, novo]) em `before`/`after`
    # - `archive` → quando `deleted_at` vira NOT NULL (soft-delete)
    # - `restore` → quando `deleted_at` vira NULL (un-archive)
    # - `destroy` → snapshot completo em `before` (raro; hard-delete via SQL)
    #
    # Atributos voláteis (`updated_at`, `created_at`) ficam fora do diff.
    module Auditable
      extend ActiveSupport::Concern

      # Atributos cuja mudança não tem valor de auditoria — só barulho.
      AUDIT_IGNORED_ATTRS = %w[updated_at created_at].freeze

      included do
        after_create_commit :_audit_log_create
        after_update_commit :_audit_log_update
        after_destroy_commit :_audit_log_destroy
      end

      private

      def _audit_log_create
        Agenda::AuditLog.async_record(self, action: 'create', after: attributes)
      end

      def _audit_log_update
        # `saved_changes` é hash { attr => [old, new] } só com os campos
        # que realmente mudaram. Vazio se nenhum atributo relevante mudou
        # (ex.: touch sem alteração de dados).
        relevant = saved_changes.except(*AUDIT_IGNORED_ATTRS)
        return if relevant.empty?

        action = _audit_log_infer_update_action(relevant)
        before, after = _audit_log_split_diff(relevant)

        Agenda::AuditLog.async_record(self, action: action, before: before, after: after)
      end

      def _audit_log_destroy
        Agenda::AuditLog.async_record(self, action: 'destroy', before: attributes)
      end

      # Distingue soft-delete (`archive`) e un-archive (`restore`) de update normal.
      # Só funciona se o model tiver coluna `deleted_at` (soft-delete padrão Klivy).
      def _audit_log_infer_update_action(relevant_changes)
        return 'update' unless relevant_changes.key?('deleted_at')

        _, new_val = relevant_changes['deleted_at']
        new_val.present? ? 'archive' : 'restore'
      end

      def _audit_log_split_diff(relevant_changes)
        before = {}
        after = {}
        relevant_changes.each do |attr, (old_val, new_val)|
          before[attr] = old_val
          after[attr] = new_val
        end
        [before, after]
      end
    end
  end
end
