# Lista as próximas consultas do paciente do contato ativo. Read-only —
# cancelar/remarcar são tools próprias (cancel_appointment /
# reschedule_appointment); use esta aqui pra pegar o `id` da consulta antes.
class AiAgent::Tools::ListAppointmentsTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Lista as próximas consultas (agendamentos) do paciente atual. Use
    quando o paciente perguntar sobre consultas marcadas, horário ou
    profissional, ou pra pegar o id da consulta antes de cancelar/remarcar
    (cancel_appointment / reschedule_appointment). Se o WhatsApp tem mais de
    uma pessoa (titular + dependente), passe `patient_id` pra ver só as
    consultas daquela pessoa.
  DESC

  param :limit,
        type: :integer,
        desc: 'Quantidade máxima de consultas a retornar (padrão 5).',
        required: false

  param :patient_id,
        type: :integer,
        required: false,
        desc: 'ID do paciente (opcional). Use com dependente no mesmo WhatsApp pra listar só as consultas dessa pessoa.'

  def execute(limit: 5, patient_id: nil)
    return { found: false, message: 'Paciente não vinculado.' } if contact_id.blank?
    return { found: false, message: 'Modelo de agenda não disponível.' } unless defined?(::AgendaEvent)

    # Busca os eventos pelo contato (contact_id no evento OU patient_id em
    # custom_attributes). Cobre tanto agendamentos da Bea quanto os criados
    # pela tela da Agenda, que não preenchem o contact_id do evento.
    events = upcoming_appointment_events(patient_id: patient_id, limit: limit.to_i.clamp(1, 20))

    { found: events.any?, count: events.size, appointments: events.map { |e| serialize_appointment(e) } }
  end

  private

  def serialize_appointment(event)
    attrs = event.custom_attributes || {}
    {
      id: event.id,
      title: event.title,
      starts_at: event.starts_at.iso8601,
      ends_at: event.ends_at.iso8601,
      status: event.status,
      event_type: event.event_type,
      professional: event.user&.name,
      patient_id: attrs['patient_id'],
      patient_name: attrs['patient_name']
    }
  end
end
