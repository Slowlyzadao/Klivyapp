# Encapsula a query de "quais documentos o paciente enxerga no portal" (PRD §8).
#
# Regras MVP (Autonomy Guided):
#   - Apenas documentos `signed`/`enviado` aparecem para o paciente.
#     (em `gerado`/`pendente_assinatura` o doc ainda não está pronto para envio)
#   - Filtra por `documents.document_types_exposed` do PatientPortalSetting.
#   - Sempre escopa por `account_id` (default-deny — cross-tenant guard duplo).
module PatientPortal
  class DocumentVisibility
    RECENT_LIMIT = 30

    EXPOSABLE_STATUSES = %w[assinado enviado].freeze

    def initialize(patient:, account:)
      @patient = patient
      @account = account
    end

    def all
      base.order(created_at: :desc).limit(RECENT_LIMIT)
    end

    def recent(limit: 5)
      base.order(created_at: :desc).limit(limit)
    end

    def find(id)
      base.find(id)
    end

    private

    def base
      Document.active
              .where(account_id: @account.id, patient_id: @patient.id)
              .where(status: EXPOSABLE_STATUSES)
              .where(document_type: exposed_types)
    end

    def exposed_types
      types = @account.patient_portal_setting&.documents&.dig('document_types_exposed')
      types.presence || Document::DOCUMENT_TYPES # se setting não existe, libera tudo (clínica é dona da config)
    end
  end
end
