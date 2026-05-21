# Encapsula a query de "quais agendamentos o paciente enxerga no portal".
# Mantém o controller magro e o filtro de visibilidade num só lugar — útil pra
# auditoria de LGPD (default-deny).
#
# Regra (PRD §7):
#   - Conta sempre escopada por `current_account`.
#   - Liga via `contact_id` porque AgendaEvent não tem patient_id direto.
#   - Eventos `kept` (não soft-deleted) sempre visíveis; cancelados aparecem
#     em histórico para o paciente saber o que aconteceu.
module PatientPortal
  class AppointmentVisibility
    UPCOMING_LIMIT = 50
    PAST_LIMIT     = 30

    def initialize(patient:, account:)
      @patient = patient
      @account = account
    end

    def upcoming
      base.where('starts_at >= ?', Time.current).order(starts_at: :asc).limit(UPCOMING_LIMIT)
    end

    def past
      base.where('starts_at < ?', Time.current).order(starts_at: :desc).limit(PAST_LIMIT)
    end

    def find(id)
      base.find(id)
    end

    # `next_event` é o próximo ativo (excluindo cancelados/no-show) — usado
    # pela home pra exibir o hero card.
    def next_event
      base.where('starts_at >= ?', Time.current)
          .where(status: %w[scheduled confirmed arrived])
          .order(starts_at: :asc)
          .first
    end

    private

    def base
      return AgendaEvent.none unless @patient.contact_id.present?

      AgendaEvent.kept
                 .where(account_id: @account.id, contact_id: @patient.contact_id)
                 .includes(:user, :agenda_service)
    end
  end
end
