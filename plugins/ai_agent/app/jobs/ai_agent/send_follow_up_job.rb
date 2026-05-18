module AiAgent
  # Recebe o id da `FollowUpExecution` (criada em `pending` pelo
  # dispatcher) e:
  #   1. Carrega contexto (contact, agenda_event, patient_memory)
  #   2. Resolve a conversa-alvo (existente ou nil — pula se não há canal)
  #   3. Chama o MessageGenerator (LLM leve gera o texto)
  #   4. Posta a mensagem na conversa via AgentBot Bea
  #   5. Marca execution como sent (com message_id) ou skipped/failed
  #
  # Tolerante a falhas — qualquer erro vira `failed` com `skip_reason`
  # legível em vez de explodir o worker. Re-tentativas ficam por conta
  # do Sidekiq (default 25x com backoff exponencial — mas como o cron
  # roda de novo a cada 15min e o dispatcher é idempotente, basta
  # falhar e deixar o próximo ciclo retentar).
  class SendFollowUpJob < ApplicationJob
    queue_as :default

    def perform(execution_id)
      execution = AiAgent::FollowUpExecution.find_by(id: execution_id)
      return if execution.nil?
      return if execution.status != 'pending'

      rule    = execution.rule
      account = execution.account
      contact = ::Contact.find_by(id: execution.contact_id) if execution.contact_id

      return mark_skipped!(execution, 'contact_not_found') if contact.nil?
      return mark_skipped!(execution, 'bea_disabled') unless AiAgent::ConfigResolver.new(account).enabled?

      conversation = resolve_conversation(execution, contact, account)
      return mark_skipped!(execution, 'no_open_conversation') if conversation.nil?

      agenda_event   = ::AgendaEvent.find_by(id: execution.agenda_event_id) if execution.agenda_event_id
      patient_memory = AiAgent::PatientMemory.find_by(account_id: account.id, contact_id: contact.id)

      result = AiAgent::FollowUps::MessageGenerator.new(
        rule: rule, contact: contact, agenda_event: agenda_event, patient_memory: patient_memory
      ).call

      return mark_failed!(execution, 'message_generation_failed') if result.nil?

      message = post_message!(conversation, result.text, account)

      execution.update!(
        status: 'sent',
        sent_at: Time.current,
        conversation_id: conversation.id,
        message_id: message.id
      )

      record_history!(patient_memory, rule, agenda_event)
      record_usage!(account, result)
    rescue StandardError => e
      Rails.logger.error("[AiAgent::SendFollowUpJob] execution=#{execution_id} #{e.class}: #{e.message[0, 200]}")
      mark_failed!(execution, "exception:#{e.class.name}") if execution
    end

    private

    # Prefere conversa existente em `open` no inbox ligado à Bea (mais
    # recente). Não criamos conversa nova porque exige inbox+template
    # WhatsApp Business — fora do escopo do MVP. Sem conversa, skip.
    def resolve_conversation(execution, contact, account)
      return ::Conversation.find_by(id: execution.conversation_id) if execution.conversation_id

      ::Conversation
        .where(account_id: account.id, contact_id: contact.id, status: %w[open pending])
        .order(last_activity_at: :desc, id: :desc)
        .first
    end

    def post_message!(conversation, text, account)
      sender = bea_agent_bot(account)
      conversation.messages.create!(
        account_id: account.id,
        inbox_id: conversation.inbox_id,
        message_type: :outgoing,
        content: text,
        sender: sender,
        private: false
      )
    end

    # Tenta usar o AgentBot "Bea" da conta como sender; se não houver
    # (configuração incompleta), retorna nil — Chatwoot aceita outgoing
    # sem sender e renderiza como mensagem de sistema.
    def bea_agent_bot(account)
      return nil unless defined?(::AgentBot)

      ::AgentBot.where(account_id: [account.id, nil]).find_by(name: 'Bea')
    rescue StandardError
      nil
    end

    def mark_skipped!(execution, reason)
      execution.update!(status: 'skipped', skip_reason: reason, sent_at: Time.current)
    end

    def mark_failed!(execution, reason)
      execution.update!(status: 'failed', skip_reason: reason, sent_at: Time.current)
    end

    def record_history!(patient_memory, rule, agenda_event)
      return if patient_memory.nil?

      summary = "Follow-up enviado: \"#{rule.name}\""
      summary += " (consulta #{agenda_event.starts_at.strftime('%d/%m %H:%M')})" if agenda_event

      patient_memory.append_history(
        event_type: 'follow_up_sent',
        summary: summary,
        metadata: { rule_id: rule.id, agenda_event_id: agenda_event&.id }
      )
    rescue StandardError
      nil
    end

    def record_usage!(account, result)
      AiAgent::UsageCounter.bump!(
        account_id: account.id,
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cost_cents: AiAgent::Pricing.cost_cents(
          model: result.model,
          input_tokens: result.input_tokens,
          output_tokens: result.output_tokens
        ),
        conversations: 0
      )
    rescue StandardError
      nil
    end
  end
end
