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

    # 2026-05-22 — `upcoming`/`past` agora usam `ends_at` em vez de
    # `starts_at`. Motivo: uma consulta em andamento (starts_at no passado,
    # ends_at no futuro) precisa continuar visível como "próxima" no portal
    # — caso contrário o paciente entra na sala, mas o card desaparece da
    # home e ele não consegue mais reabrir o link a partir do app
    # ("acabei de entrar e já tá no histórico"). Reportado em sessão real:
    # paciente perdeu o agendamento porque starts_at era 19:06 e ele abriu
    # o portal 19:13 — a regra `starts_at >= now` jogava direto pro
    # histórico mesmo com ends_at = 20:06 ainda no futuro.
    def upcoming
      base.where('ends_at >= ?', Time.current).order(starts_at: :asc).limit(UPCOMING_LIMIT)
    end

    def past
      base.where('ends_at < ?', Time.current).order(starts_at: :desc).limit(PAST_LIMIT)
    end

    def find(id)
      base.find(id)
    end

    # `next_event` é o próximo ativo (excluindo cancelados/no-show) — usado
    # pela home pra exibir o hero card. Mesma lógica do `upcoming`: em
    # andamento conta como próximo. Status `arrived`/`in_progress` mantêm
    # o evento ativo até ser explicitamente `completed`/`no_show`.
    def next_event
      base.where('ends_at >= ?', Time.current)
          .where(status: %w[scheduled confirmed arrived in_progress])
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
