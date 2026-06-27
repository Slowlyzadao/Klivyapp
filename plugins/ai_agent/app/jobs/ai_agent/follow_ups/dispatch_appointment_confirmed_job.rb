# Dispatch event-driven (não-cron) pro trigger `appointment_confirmed`.
# Roda quando `AgendaEvent` transiciona de `pending_confirmation` pra
# `scheduled`/`confirmed` (callback `approved_after_pending?`).
#
# Pra cada FollowUpRule com trigger `appointment_confirmed` ativa na
# conta, cria FollowUpExecution e enfileira SendFollowUpJob. Respeita:
#   - applies_to (filtro de origem do AgendaEvent)
#   - max_per_target (cap por consulta)
#   - idempotência via UNIQUE (rule_id + contact_id + agenda_event_id + target_at)
#
# Diferença em relação ao FollowUpDispatcherJob (cron):
#   - Cron itera todas as rules e procura candidatos elegíveis no tempo
#   - Aqui já temos o evento exato — é só procurar rules que casam
class AiAgent::FollowUps::DispatchAppointmentConfirmedJob < ApplicationJob
  queue_as :default

  def perform(agenda_event_id)
    event = ::AgendaEvent.find_by(id: agenda_event_id)
    # deleted_at: o evento pode ter sido soft-deletado entre o enqueue do
    # callback e o perform — consulta excluída não confirma nada.
    return if event.nil? || event.deleted_at.present?
    return unless %w[scheduled confirmed].include?(event.status)

    contact_id = resolve_contact_id(event)
    return if contact_id.blank?

    rules = AiAgent::FollowUpRule
            .enabled
            .where(account_id: event.account_id, trigger_type: 'appointment_confirmed')
            .ordered

    rules.each do |rule|
      dispatch_for_rule(rule, event, contact_id)
    rescue StandardError => e
      Rails.logger.error("[AiAgent::FollowUps::DispatchAppointmentConfirmedJob] rule=#{rule.id} event=#{event.id} #{e.class}: #{e.message[0,
                                                                                                                                          200]}")
    end
  end

  private

  # Evento criado pela UI/Bea costuma ter contact_id NIL com o paciente em
  # custom_attributes.patient_id — resolve o contato via Patient (escopado
  # pela conta). Sem contato resolvível não há canal de envio.
  def resolve_contact_id(event)
    return event.contact_id if event.contact_id.present?
    return nil unless defined?(::Patient)

    patient_id = event.custom_attributes&.dig('patient_id')
    return nil if patient_id.blank?

    ::Patient.where(account_id: event.account_id, id: patient_id).pick(:contact_id)
  rescue StandardError
    nil
  end

  def dispatch_for_rule(rule, event, contact_id)
    # Filtro applies_to: só dispara se origem do evento bate com o
    # filtro da regra. Ex: regra `applies_to=ai_agent` ignora eventos
    # criados manualmente pela recepção.
    sources = rule.agenda_source_filter
    return if sources&.exclude?(event.source)
    return if already_dispatched?(rule, event)
    return if cap_reached?(rule, event, contact_id)

    execution = AiAgent::FollowUpExecution.create!(
      rule_id: rule.id,
      account_id: rule.account_id,
      contact_id: contact_id,
      agenda_event_id: event.id,
      target_at: Time.current,
      status: 'pending'
    )

    AiAgent::SendFollowUpJob.perform_later(execution.id)
  rescue ActiveRecord::RecordNotUnique
    # Race com outro callback (raro mas possível em setups com replica).
    nil
  end

  # Idempotência por evento: o UNIQUE do banco inclui `target_at`, mas
  # como aqui ele é Time.current (muda a cada chamada), não bloqueia
  # duplicação — checa à mão: 1 confirmação por (rule, evento),
  # independente de quantas vezes o callback dispara.
  def already_dispatched?(rule, event)
    AiAgent::FollowUpExecution.exists?(rule_id: rule.id, agenda_event_id: event.id, status: %w[pending sent])
  end

  # Cap por alvo extra: caso `max_per_target > 1`, conta envios passados
  # (rule + contact + event). Se já mandou max, pula.
  def cap_reached?(rule, event, contact_id)
    return false unless rule.max_per_target.to_i.positive?

    AiAgent::FollowUpExecution
      .where(rule_id: rule.id, status: 'sent', contact_id: contact_id, agenda_event_id: event.id)
      .count >= rule.max_per_target.to_i
  end
end
