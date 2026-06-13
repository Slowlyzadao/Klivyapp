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
class AiAgent::Tools::CancelAppointmentTool < AiAgent::Tools::BaseTool
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
        desc: 'Motivo do cancelamento informado pelo paciente. OBRIGATÓRIO: pergunte o motivo ANTES de chamar — sem ele a tool recusa.'

  ALREADY_CLOSED_STATUSES = %w[cancelled completed no_show].freeze

  def execute(appointment_id:, reason: '')
    return failure('Módulo de agenda não disponível.') unless defined?(::AgendaEvent)
    return failure('Paciente não vinculado a esta conversa.') if contact_id.blank?

    # Motivo é OBRIGATÓRIO (regra do produto: vai pras Observações do
    # paciente). Caso real: a Bea pulou a pergunta e cancelou sem motivo.
    if reason.to_s.strip.blank?
      return { cancelled: false, needs_reason: true,
               note_for_bea: 'NÃO cancele ainda: pergunte o MOTIVO do cancelamento ao paciente (obrigatório, vai pras ' \
                             'Observações) e chame de novo com reason preenchido.' }
    end

    event = ::AgendaEvent.kept.where(account_id: account.id).find_by(id: appointment_id)
    return failure("Consulta #{appointment_id} não encontrada.") if event.nil?
    return failure('Essa consulta não pertence a este paciente.') unless owns_appointment?(event)
    return failure("Consulta já está como '#{event.status}'.") if ALREADY_CLOSED_STATUSES.include?(event.status)
    return failure('Não posso cancelar consulta que já passou.') if event.starts_at < Time.current

    merged_description = [event.description.to_s.strip, reason.present? ? "Motivo: #{reason}" : nil].compact.reject(&:empty?).join("\n")[0, 1000]

    event.update!(
      status: 'cancelled',
      description: merged_description,
      contact_id: event.contact_id || contact_id
    )

    record_cancellation_in_patient_notes(event, reason) if reason.present?

    patient_memory&.append_history(
      event_type: 'appointment_cancelled',
      summary: "#{event.title} (#{event.starts_at.strftime('%d/%m %H:%M')}) cancelada",
      metadata: { agenda_event_id: event.id, reason: reason.presence }
    )

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

  # Registra o motivo do cancelamento nas Observações do paciente (campo
  # `notes` do cadastro/prontuário). update_columns pula as validações do
  # plugin patients — não queremos travar o cancelamento por causa disso.
  def record_cancellation_in_patient_notes(event, reason)
    return unless defined?(::Patient)

    pid = (event.custom_attributes || {})['patient_id']
    patient = if pid.present?
                ::Patient.find_by(account_id: account.id, id: pid)
              else
                ::Patient.find_by(account_id: account.id, contact_id: contact_id)
              end
    return if patient.nil?

    quando = event.starts_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y %H:%M')
    entry = "[#{quando}] Consulta cancelada. Motivo: #{reason}"
    combined = [patient.notes.to_s.strip, entry].reject(&:empty?).join("\n")
    combined = combined[-5000..] if combined.length > 5000
    patient.update_columns(notes: combined, updated_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("[cancel_appointment] não consegui gravar notes do paciente: #{e.message}")
  end
end
