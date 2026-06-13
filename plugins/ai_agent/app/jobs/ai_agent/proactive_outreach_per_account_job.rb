# ESC-3 (auditoria 2026-05-18): worker per-account criado pra escalar
# recall proativo diário. Antes o dispatcher iterava todas as contas
# com Bea habilitada sequencialmente. Em escala vira problema. Agora
# o cron despacha 1 job por conta e Sidekiq paraleliza.
class AiAgent::ProactiveOutreachPerAccountJob < ApplicationJob
  queue_as :scheduled_jobs

  DAILY_PER_ACCOUNT_CAP = AiAgent::ProactiveOutreachJob::DAILY_PER_ACCOUNT_CAP
  RECALL_MESSAGE_KEY = AiAgent::ProactiveOutreachJob::RECALL_MESSAGE_KEY

  def perform(account_id)
    account = ::Account.find_by(id: account_id)
    return unless account

    candidates = AiAgent::Proactive::RecallFinder.new(account: account, limit: DAILY_PER_ACCOUNT_CAP).call
    return if candidates.empty?

    Rails.logger.info(
      "[AiAgent::ProactiveOutreachPerAccountJob] account=#{account.id} candidatos=#{candidates.size}"
    )

    candidates.each { |c| send_recall(account, c) }
  rescue StandardError => e
    Rails.logger.error(
      "[AiAgent::ProactiveOutreachPerAccountJob] account=#{account_id} falhou: " \
      "#{e.class}: #{e.message}"
    )
  end

  private

  def send_recall(account, candidate)
    conversation = recent_conversation_for(account, candidate.contact)
    if conversation.nil?
      Rails.logger.info(
        "[AiAgent::ProactiveOutreachPerAccountJob] sem conversa pra contact=#{candidate.contact.id}, pulando"
      )
      return
    end

    message_body = build_recall_message(account, candidate)

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: conversation.inbox_id,
      sender: AiAgent::AgentBotIdentity.ensure!,
      content: message_body
    )

    memory = AiAgent::PatientMemory.for(account: account, contact_id: candidate.contact.id)
    prefs = memory.preferences.is_a?(Hash) ? memory.preferences : {}
    prefs[RECALL_MESSAGE_KEY] = Time.current.iso8601
    memory.update!(preferences: prefs)
    memory.append_history(
      event_type: 'recall_sent',
      summary: "Recall enviado após #{candidate.dormant_days} dias sem retorno",
      metadata: { conversation_id: conversation.id, last_visit_at: candidate.last_event_date.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.error(
      "[AiAgent::ProactiveOutreachPerAccountJob] envio falhou contact=#{candidate.contact.id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  # Procura conversa do contato (qualquer status) preferindo a mais
  # recente. Em produção real (canal WhatsApp), só conversa com
  # mensagem nas últimas 24h aceita texto livre. Pra piloto, usamos
  # a mais recente; o canal vai falhar silenciosamente fora da janela.
  def recent_conversation_for(account, contact)
    ::Conversation.where(account_id: account.id, contact_id: contact.id)
                  .order(updated_at: :desc).first
  end

  # Mensagem curta, com nome se disponível, citando dormência e
  # com opt-out explícito. Não cita procedimentos específicos —
  # mensagem genérica que cabe em qualquer especialidade.
  def build_recall_message(account, candidate)
    first_name = candidate.contact.name.to_s.split(/[ |]/).first.to_s.presence
    months = (candidate.dormant_days / 30).clamp(1, 24)
    clinic_name = clinic_name_for(account).presence || 'da clínica'

    greeting = first_name ? "Oi #{first_name}!" : 'Oi!'

    "#{greeting} Aqui é a Bea, assistente virtual #{clinic_name}. Vi que sua última consulta foi há cerca de #{months} #{months == 1 ? 'mês' : 'meses'} — quer que eu já te ajude a agendar um retorno? Se preferir não receber esse tipo de lembrete, é só responder NÃO que eu não te chamo mais."
  end

  def clinic_name_for(account)
    return nil unless defined?(::Captain::Assistant)

    assistant = ::Captain::Assistant.where(account_id: account.id, name: 'Beatriz').first
    profile = assistant&.config&.dig('clinic_profile') || {}
    profile['name'].to_s.strip.presence&.then { |n| "da #{n}" }
  end
end
