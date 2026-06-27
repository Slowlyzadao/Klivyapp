module Financial
  class AuditLogJob < ApplicationJob
    queue_as :default

    # Insert do AuditLog em background — não bloqueia a transação principal.
    # Canon F-02: "Insert no AuditLog não bloqueia transação principal".
    def perform(payload)
      Financial::AuditLog.create!(payload.symbolize_keys)
    rescue ActiveRecord::RecordNotUnique
      # ignora — algum retry pode ter inserido o mesmo log; AuditLog não tem
      # constraint de unicidade, mas mantemos defensivo.
    rescue StandardError => e
      Rails.logger.error("[Financial::AuditLogJob] #{e.class} #{e.message}")
      # NÃO re-lança — auditoria não pode quebrar fluxo principal.
    end
  end
end
