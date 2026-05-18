module AiAgent
  module Tools
    # Lista consultas (futuras + recentes passadas) de um paciente específico.
    # Pra Pipeline B (Chat Interno). Diferente de ListAppointmentsTool, recebe
    # `patient_id` explícito (não depende do contact_id da sessão).
    #
    # Use depois de InternalSearchPatientTool encontrar o patient_id certo.
    # Equipe pergunta "@bea esse paciente tem consulta marcada?" → Bea busca →
    # depois lista as próximas.
    class InternalListPatientAppointmentsTool < BaseTool
      description <<~DESC
        Lista consultas (próximas + últimas) de um paciente específico. Use
        DEPOIS de internal_search_patient ter encontrado o patient_id. Aceita
        opcionalmente quantas próximas e quantas passadas retornar.
      DESC

      param :patient_id,
            type: :integer,
            desc: 'ID do paciente. Pegue do retorno de internal_search_patient.'

      param :upcoming_limit,
            type: :integer,
            required: false,
            desc: 'Quantas consultas FUTURAS retornar (padrão 5).'

      param :past_limit,
            type: :integer,
            required: false,
            desc: 'Quantas consultas PASSADAS retornar (padrão 3).'

      def execute(patient_id:, upcoming_limit: 5, past_limit: 3)
        return { found: false, message: 'Módulo de pacientes não disponível.' } unless defined?(::Patient)
        return { found: false, message: 'Módulo de agenda não disponível.' } unless defined?(::AgendaEvent)

        patient = ::Patient.active.find_by(account_id: account.id, id: patient_id)
        return { found: false, message: "Paciente #{patient_id} não encontrado." } unless patient

        contact_id = patient.contact_id

        upcoming = ::AgendaEvent
                   .where(account_id: account.id, contact_id: contact_id)
                   .where('starts_at >= ?', Time.current)
                   .order(:starts_at)
                   .limit(upcoming_limit.to_i.clamp(1, 20))

        past = ::AgendaEvent
               .where(account_id: account.id, contact_id: contact_id)
               .where('starts_at < ?', Time.current)
               .order(starts_at: :desc)
               .limit(past_limit.to_i.clamp(0, 10))

        {
          found: true,
          patient: { id: patient.id, name: patient.try(:full_name).presence || patient.name },
          upcoming_count: upcoming.size,
          past_count: past.size,
          upcoming: upcoming.map { |e| serialize_event(e) },
          past: past.map { |e| serialize_event(e) }
        }
      end

      private

      def serialize_event(event)
        {
          id: event.id,
          title: event.title,
          starts_at: event.starts_at.iso8601,
          status: event.status,
          professional: event.user&.name
        }
      end
    end
  end
end
