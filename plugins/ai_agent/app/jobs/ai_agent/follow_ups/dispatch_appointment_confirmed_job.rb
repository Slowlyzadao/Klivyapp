module AiAgent
  module FollowUps
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
    class DispatchAppointmentConfirmedJob < ApplicationJob
      queue_as :default

      def perform(agenda_event_id)
        event = ::AgendaEvent.find_by(id: agenda_event_id)
        return if event.nil?
        return if event.contact_id.blank?
        return unless %w[scheduled confirmed].include?(event.status)

        rules = AiAgent::FollowUpRule
                .enabled
                .where(account_id: event.account_id, trigger_type: 'appointment_confirmed')
                .ordered

        rules.each do |rule|
          dispatch_for_rule(rule, event)
        rescue StandardError => e
          Rails.logger.error("[AiAgent::FollowUps::DispatchAppointmentConfirmedJob] rule=#{rule.id} event=#{event.id} #{e.class}: #{e.message[0, 200]}")
        end
      end

      private

      def dispatch_for_rule(rule, event)
        # Filtro applies_to: só dispara se origem do evento bate com o
        # filtro da regra. Ex: regra `applies_to=ai_agent` ignora eventos
        # criados manualmente pela recepção.
        sources = rule.agenda_source_filter
        return if sources && !sources.include?(event.source)

        # Idempotência por evento: o UNIQUE do banco inclui `target_at`,
        # mas como `target_at` é Time.current (muda a cada chamada),
        # ele não bloqueia duplicação aqui — preciso checar à mão.
        # Diferente do cron (cujo target_at é determinístico = starts_at
        # ± offset), aqui dispatch é event-driven: 1 confirmação por
        # (rule, evento), independente de quantas vezes o callback dispara.
        if AiAgent::FollowUpExecution.exists?(
          rule_id: rule.id,
          agenda_event_id: event.id,
          status: %w[pending sent]
        )
          return
        end

        # Cap por alvo extra: caso `max_per_target > 1`, conta envios
        # passados (rule + contact + event). Se já mandou max, pula.
        if rule.max_per_target.to_i.positive?
          sent = AiAgent::FollowUpExecution
                 .where(rule_id: rule.id, status: 'sent',
                        contact_id: event.contact_id, agenda_event_id: event.id)
                 .count
          return if sent >= rule.max_per_target.to_i
        end

        execution = AiAgent::FollowUpExecution.create!(
          rule_id: rule.id,
          account_id: rule.account_id,
          contact_id: event.contact_id,
          agenda_event_id: event.id,
          target_at: Time.current,
          status: 'pending'
        )

        AiAgent::SendFollowUpJob.perform_later(execution.id)
      rescue ActiveRecord::RecordNotUnique
        # Race com outro callback (raro mas possível em setups com replica).
        nil
      end
    end
  end
end
