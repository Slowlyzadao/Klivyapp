# Anamneses visíveis ao paciente (PRD §8.3 — opt-in via clínica).
#
# Setting: `clinical.expose_anamnesis_to_patient` (default false). Quando false,
# o paciente NÃO vê histórico de anamnese — só o aviso de que existe.
#
# Esta política está em linha com default-deny: dados clínicos só vazam se a
# clínica explicitamente liberou.
module PatientPortal
  class AnamnesisVisibility
    LIST_LIMIT = 20

    def initialize(patient:, account:)
      @patient = patient
      @account = account
    end

    def exposed?
      val = @account.patient_portal_setting&.clinical&.dig('expose_anamnesis_to_patient')
      val == true
    end

    def has_any?
      return false unless defined?(Anamnesis)

      Anamnesis.active.where(account_id: @account.id, patient_id: @patient.id, status: 'finalized').exists?
    end

    def all
      return Anamnesis.none unless exposed? && defined?(Anamnesis)

      Anamnesis.active
               .where(account_id: @account.id, patient_id: @patient.id, status: 'finalized')
               .order(version_number: :desc)
               .limit(LIST_LIMIT)
    end

    def find(id)
      raise ActiveRecord::RecordNotFound unless exposed?

      Anamnesis.active.where(account_id: @account.id, patient_id: @patient.id).find(id)
    end
  end
end
