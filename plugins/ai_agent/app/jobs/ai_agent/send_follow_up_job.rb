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
class AiAgent::SendFollowUpJob < ApplicationJob
  queue_as :default

  # Contexto resolvido de um disparo (alvo + canal). Montado por
  # `load_context`, consumido por `deliver`.
  Ctx = Struct.new(:rule, :account, :contact, :conversation, :agenda_event, :patient_memory, :step,
                   keyword_init: true)

  def perform(execution_id)
    execution = AiAgent::FollowUpExecution.find_by(id: execution_id)
    return if execution.nil? || execution.status != 'pending'

    deliver(execution)
  rescue StandardError => e
    Rails.logger.error("[AiAgent::SendFollowUpJob] execution=#{execution_id} #{e.class}: #{e.message[0, 200]}")
    mark_failed!(execution, "exception:#{e.class.name}") if execution
  end

  private

  def deliver(execution)
    ctx = load_context(execution)
    return if ctx.nil? # guards já marcaram skipped

    # Composição (texto livre vs template fora da janela) mora no
    # OutboundMessage — o job só posta o que ele decidir.
    result = AiAgent::FollowUps::OutboundMessage.new(
      rule: ctx.rule, step: ctx.step, contact: ctx.contact,
      agenda_event: ctx.agenda_event
    ).call(ctx.conversation)
    return handle_skip(execution, result.skip_reason) if result.skip_reason

    post_and_record(execution, ctx, result)
  end

  # Resolve alvo + canal, aplicando os guards de skip. Retorna nil (já
  # tendo marcado a execução) quando o disparo não pode acontecer.
  def load_context(execution)
    account = execution.account
    contact = ::Contact.find_by(id: execution.contact_id) if execution.contact_id
    return skip(execution, 'contact_not_found') if contact.nil?
    return skip(execution, 'bea_disabled') unless AiAgent::ConfigResolver.new(account).enabled?

    conversation = resolve_conversation(execution, contact, account)
    return skip(execution, 'no_open_conversation') if conversation.nil?

    Ctx.new(
      rule: execution.rule, account: account, contact: contact, conversation: conversation,
      agenda_event: (::AgendaEvent.find_by(id: execution.agenda_event_id) if execution.agenda_event_id),
      patient_memory: AiAgent::PatientMemory.find_by(account_id: account.id, contact_id: contact.id),
      step: (AiAgent::FollowUpStep.find_by(id: execution.step_id) if execution.step_id)
    )
  end

  def post_and_record(execution, ctx, result)
    message = post_message!(ctx.conversation, result.content, ctx.account, result.template_params)
    execution.update!(
      status: 'sent', sent_at: Time.current,
      conversation_id: ctx.conversation.id, message_id: message.id
    )
    record_history!(ctx.patient_memory, ctx.rule, ctx.agenda_event)
    record_usage!(ctx.account, result.usage) if result.usage
  end

  # Marca skipped e retorna nil (pra `load_context` abortar).
  def skip(execution, reason)
    mark_skipped!(execution, reason)
    nil
  end

  # Falha de geração do LLM vira `failed`; demais motivos (ex: fora da
  # janela sem template) viram `skipped`.
  def handle_skip(execution, reason)
    return mark_failed!(execution, reason) if reason == 'message_generation_failed'

    mark_skipped!(execution, reason)
  end

  # Prefere conversa aberta/pendente (mais recente); sem nenhuma, usa a
  # mais recente de QUALQUER status — reativação de paciente dormente
  # quase sempre só tem a conversa resolved de meses atrás, e quem decide
  # texto livre vs template é a janela de 24h (OutboundMessage), não o
  # status. Não criamos conversa nova (exige inbox+template WhatsApp
  # Business — fora do MVP). Sem conversa alguma, skip.
  def resolve_conversation(execution, contact, account)
    return ::Conversation.find_by(id: execution.conversation_id) if execution.conversation_id

    scope = ::Conversation
            .where(account_id: account.id, contact_id: contact.id)
            .order(last_activity_at: :desc, id: :desc)
    scope.where(status: %w[open pending]).first || scope.first
  end

  # Posta a mensagem. Com `template_params`, anexa em additional_attributes
  # pro Chatwoot enviar como template aprovado (Whatsapp::SendOnWhatsappService).
  def post_message!(conversation, text, account, template_params = nil)
    attrs = {
      account_id: account.id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content: text,
      sender: bea_agent_bot(account),
      private: false,
      # Marca a origem: o histórico da Bea rotula esta mensagem como
      # follow-up automático. Sem isso o LLM lê o "Olá, Fulano" do
      # follow-up como reabertura da conversa e recumprimenta o paciente
      # ("Bom dia" de novo no meio do fluxo).
      content_attributes: { 'ai_follow_up' => true }
    }
    attrs[:additional_attributes] = { 'template_params' => template_params } if template_params.present?
    conversation.messages.create!(attrs)
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

  # Os mark_* NUNCA propagam erro de persistência: se a mensagem já foi
  # postada e o update do status explodir, um raise dispararia o retry do
  # Sidekiq e o perform re-postaria a MESMA mensagem (double-send). Vira
  # log; a execução fica pending e o already_executed? impede re-disparo.
  def mark_skipped!(execution, reason)
    execution.update!(status: 'skipped', skip_reason: reason, sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[AiAgent::SendFollowUpJob] mark_skipped failed execution=#{execution.id}: #{e.message[0, 120]}")
    nil
  end

  def mark_failed!(execution, reason)
    execution.update!(status: 'failed', skip_reason: reason, sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[AiAgent::SendFollowUpJob] mark_failed failed execution=#{execution.id}: #{e.message[0, 120]}")
    nil
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
