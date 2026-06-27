# Consentimentos clínicos visíveis ao paciente (PRD §11).
#
# Diferente de `PatientPortalConsent` (que cobre os termos Klivy — portal_terms
# + lgpd). Aqui é o `ConsentRecord` por procedimento, com assinatura remota.
#
# Regras:
#   - Paciente vê `pendente`, `signed`, `vencido` (precisa enxergar histórico).
#   - `revogado` aparece em "histórico" para transparência.
#   - Soft-deleted nunca aparece (default-deny via `active`).
module PatientPortal
  class ConsentRecordVisibility
    LIST_LIMIT = 30

    def initialize(patient:, account:)
      @patient = patient
      @account = account
    end

    def pending
      base.where(status: %w[pendente vencido]).order(created_at: :desc)
    end

    def signed
      base.where(status: 'signed').order(signed_at: :desc).limit(LIST_LIMIT)
    end

    def all
      base.order(created_at: :desc).limit(LIST_LIMIT)
    end

    def find(id)
      base.find(id)
    end

    private

    def base
      return ConsentRecord.none unless defined?(ConsentRecord)

      ConsentRecord.active.where(account_id: @account.id, patient_id: @patient.id)
    end
  end
end
