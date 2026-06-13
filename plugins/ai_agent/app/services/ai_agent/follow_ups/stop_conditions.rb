# Condições de saída da cadência (Fase 3). Dado um candidato a follow-up,
# decide se a sequência deve PARAR porque o paciente já se engajou:
#   stop_on_reply   → respondeu (mandou mensagem) depois do nosso último envio
#   stop_on_booking → tem agendamento futuro (scheduled/confirmed)
#
# Extraído do CandidateFinder pra manter cada classe com uma
# responsabilidade só (achar candidatos vs avaliar parada).
#
# O passo 1 nunca é barrado por `stop_on_reply` (não há envio anterior),
# então a primeira abordagem da Bea sempre acontece.
class AiAgent::FollowUps::StopConditions
  def initialize(rule, now: Time.current)
    @rule = rule
    @now = now
  end

  def stopped?(candidate)
    return true if @rule.stop_on_booking && future_booking?(candidate)
    return true if @rule.stop_on_reply && replied_after_last_send?(candidate)

    false
  end

  private

  # Paciente tem agendamento futuro (scheduled/confirmed). Exclui o próprio
  # evento do candidato — assim, em triggers de agenda (pre/post/no_show) a
  # consulta-alvo não conta como "já agendou", e em no_response/reativação
  # qualquer marcação futura para a sequência. Cobre os DOIS vínculos do
  # evento: contact_id e custom_attributes.patient_id (eventos criados pela
  # UI da agenda costumam ter contact_id nil).
  def future_booking?(candidate)
    cid = candidate[:contact_id]
    return false if cid.blank?
    return false unless defined?(::AgendaEvent)

    scope = ::AgendaEvent
            .where(account_id: @rule.account_id, status: %w[scheduled confirmed], deleted_at: nil)
            .where('starts_at > ?', @now)
    scope = scope.where.not(id: candidate[:agenda_event_id]) if candidate[:agenda_event_id]
    return true if scope.exists?(contact_id: cid)

    booking_by_patient?(scope, cid)
  end

  # Resolve o Patient do contato e procura o agendamento pelo
  # custom_attributes.patient_id — espelha o rebooked_service? do
  # ServiceRecallFinder.
  def booking_by_patient?(scope, contact_id)
    return false unless defined?(::Patient)

    patient_id = ::Patient.where(account_id: @rule.account_id, contact_id: contact_id).pick(:id)
    return false if patient_id.nil?

    scope.exists?(["agenda_events.custom_attributes ->> 'patient_id' = ?", patient_id.to_s])
  rescue StandardError
    false
  end

  # Paciente mandou alguma mensagem (incoming) DEPOIS do nosso último envio
  # dessa regra PARA ESTE ALVO. Escopo por evento (triggers de agenda) ou
  # pela âncora do episódio (no_response/recall) — sem isso, um "obrigado"
  # de meses atrás barraria pra sempre o passo 1 de qualquer alvo novo.
  # Sem envio anterior do alvo → false (o passo 1 segue).
  def replied_after_last_send?(candidate)
    cid = candidate[:contact_id]
    return false if cid.blank?
    return false unless defined?(::Message) && defined?(::Conversation)

    last_send = sends_for_target(candidate).maximum(:sent_at)
    return false if last_send.nil?

    ::Message
      .joins(:conversation)
      .where(conversations: { account_id: @rule.account_id, contact_id: cid })
      .where(message_type: 'incoming', private: false)
      .exists?(['messages.created_at > ?', last_send])
  end

  def sends_for_target(candidate)
    scope = AiAgent::FollowUpExecution.where(rule_id: @rule.id, contact_id: candidate[:contact_id], status: 'sent')
    return scope.where(agenda_event_id: candidate[:agenda_event_id]) if candidate[:agenda_event_id]
    return scope.where(sent_at: candidate[:anchor_at]..) if candidate[:anchor_at]

    scope
  end
end
