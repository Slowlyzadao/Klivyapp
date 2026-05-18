module AiAgent
  module Tools
    # Marks an existing AgendaEvent as `cancelled`. Soft-cancel — the
    # record stays in the calendar with status=cancelled so the clinic
    # can audit later. The slot is freed (search_available_slots ignores
    # cancelled events).
    #
    # Guardrails:
    #   - Only cancels events of the active contact (security)
    #   - Refuses if event already passed
    #   - Refuses if already cancelled / completed / no_show (idempotent
    #     guard with clear error message)
    class CancelAppointmentTool < BaseTool
      description <<~DESC
        Cancela uma consulta agendada do paciente atual. Use quando o
        paciente pedir pra cancelar/desmarcar.

        Sequência obrigatória ANTES de chamar:
          1. list_appointments → pega o id da consulta a cancelar
             (se houver mais de uma futura, pergunte ao paciente qual)
          2. Confirme com o paciente que ele quer mesmo cancelar
        NÃO chame essa tool sem confirmação explícita do paciente.
      DESC

      param :appointment_id,
            type: :integer,
            desc: 'ID da consulta a cancelar. Vem de list_appointments → appointments[].id.'

      param :reason,
            type: :string,
            required: false,
            desc: 'Motivo do cancelamento (opcional, vai pra description).'

      ALREADY_CLOSED_STATUSES = %w[cancelled completed no_show].freeze

      def execute(appointment_id:, reason: '')
        return failure('Módulo de agenda não disponível.') unless defined?(::AgendaEvent)
        return failure('Paciente não vinculado a esta conversa.') if contact_id.blank?

        event = ::AgendaEvent.where(account_id: account.id).find_by(id: appointment_id)
        return failure("Consulta #{appointment_id} não encontrada.") if event.nil?
        return failure('Essa consulta não pertence a este paciente.') if event.contact_id != contact_id
        return failure("Consulta já está como '#{event.status}'.") if ALREADY_CLOSED_STATUSES.include?(event.status)
        return failure('Não posso cancelar consulta que já passou.') if event.starts_at < Time.current

        merged_description = [event.description.to_s.strip, reason.present? ? "Motivo: #{reason}" : nil].compact.reject(&:empty?).join("\n")[0, 1000]

        event.update!(
          status: 'cancelled',
          description: merged_description
        )

        if patient_memory
          patient_memory.append_history(
            event_type: 'appointment_cancelled',
            summary: "#{event.title} (#{event.starts_at.strftime('%d/%m %H:%M')}) cancelada",
            metadata: { agenda_event_id: event.id, reason: reason.presence }
          )
        end

        {
          cancelled: true,
          appointment: {
            id: event.id,
            title: event.title,
            was_scheduled_for: event.starts_at.iso8601,
            professional: event.user&.name,
            status: event.status,
            note_for_patient: 'Consulta cancelada com sucesso.'
          }
        }
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message)
      end

      private

      def failure(msg)
        { cancelled: false, error: msg }
      end
    end
  end
end
