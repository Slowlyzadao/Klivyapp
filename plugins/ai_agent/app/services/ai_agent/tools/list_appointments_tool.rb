module AiAgent
  module Tools
    # Read-only view of upcoming appointments for the active patient.
    # Booking is intentionally NOT exposed by Bea yet (Phase 4.5) — too easy
    # to schedule garbage with sloppy NL parsing.
    class ListAppointmentsTool < BaseTool
      description <<~DESC
        Lista as próximas consultas (agendamentos) do paciente atual. Use
        quando o paciente perguntar sobre suas consultas marcadas, horários,
        profissional, ou quiser confirmar/desmarcar (mas a Bea NÃO desmarca
        sozinha — apenas informa e transfere para humano se necessário).
      DESC

      param :limit,
            type: :integer,
            desc: 'Quantidade máxima de consultas a retornar (padrão 5).',
            required: false

      def execute(limit: 5)
        return { found: false, message: 'Paciente não vinculado.' } if contact_id.blank?
        return { found: false, message: 'Modelo de agenda não disponível.' } unless defined?(::AgendaEvent)

        events = ::AgendaEvent
                 .where(account_id: account.id, contact_id: contact_id)
                 .where('starts_at >= ?', Time.current)
                 .order(:starts_at)
                 .limit(limit.to_i.clamp(1, 20))

        {
          found: events.any?,
          count: events.size,
          appointments: events.map do |e|
            {
              id: e.id,
              title: e.title,
              starts_at: e.starts_at.iso8601,
              ends_at: e.ends_at.iso8601,
              status: e.status,
              event_type: e.event_type,
              professional: e.user&.name
            }
          end
        }
      end
    end
  end
end
