# Pipeline A — quando a Bea reserva um agendamento via BookAppointmentTool
# (status='pending_confirmation', source='ai_agent'), posta uma mensagem
# templated no destino configurado pela clínica.
#
# Apenas monta as `vars` específicas do evento e delega ao Dispatcher
# genérico, que cuida de Router → render → dedupe → MessageDispatcher.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.2)
class AiAgent::InternalNotifier::AppointmentPendingConfirmation
  EVENT_KEY = 'appointment_pending_confirmation'.freeze

  def self.call(agenda_event)
    new(agenda_event).call
  end

  def initialize(agenda_event)
    @event = agenda_event
  end

  def call
    return unless eligible?

    AiAgent::InternalNotifier::Dispatcher.dispatch(
      account: @event.account,
      event_key: EVENT_KEY,
      vars: build_vars,
      dedupe_key: "#{EVENT_KEY}:#{@event.id}"
    )
  end

  private

  def eligible?
    @event.status == 'pending_confirmation' &&
      @event.source == 'ai_agent' &&
      @event.contact_id.present?
  end

  def build_vars
    {
      patient_name: patient&.name || @event.contact&.name || 'Paciente',
      patient_phone: patient_phone,
      patient_status: patient_is_new? ? '(acabei de criar a ficha)' : '',
      service_name: @event.title.to_s,
      dentist_name: @event.user&.name || 'a definir',
      appointment_starts_at: format_starts_at,
      last_visit_line: last_visit_line
    }
  end

  def patient
    @patient ||= defined?(::Patient) ? ::Patient.find_by(contact_id: @event.contact_id, account_id: @event.account_id) : nil
  end

  def patient_is_new?
    return false unless patient

    patient.created_at > 5.minutes.ago
  end

  def patient_phone
    patient&.phone.presence || @event.contact&.phone_number.presence || 'sem telefone'
  end

  def format_starts_at
    I18n.l(@event.starts_at.in_time_zone('America/Sao_Paulo'), format: '%d/%m/%Y às %H:%M')
  rescue StandardError
    @event.starts_at.strftime('%d/%m/%Y %H:%M')
  end

  def last_visit_line
    return '' unless patient

    last = ::AgendaEvent.where(account_id: @event.account_id, contact_id: @event.contact_id)
                        .where.not(id: @event.id)
                        .where(status: 'completed')
                        .order(starts_at: :desc).first
    return '' unless last

    date = last.starts_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')
    "📌 Última visita: #{date}"
  end
end
