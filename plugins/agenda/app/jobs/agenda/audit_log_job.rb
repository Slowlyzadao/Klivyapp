module Agenda
  # Insert do Agenda::AuditLog em background — não bloqueia a transação
  # principal do save da entidade auditada. Mesmo padrão do Financial::AuditLogJob.
  # NUNCA re-lança: auditoria não pode quebrar o fluxo principal.
  class AuditLogJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Agenda::AuditLog.create!(payload.symbolize_keys)
    rescue ActiveRecord::RecordNotUnique
      # Defensivo — sem unique constraint na tabela hoje, mas se algum retry
      # do ActiveJob duplicar, ignora silenciosamente.
    rescue StandardError => e
      Rails.logger.error("[Agenda::AuditLogJob] #{e.class} #{e.message}")
    end
  end
end
