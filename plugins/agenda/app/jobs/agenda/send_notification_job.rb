# Agenda::SendNotificationJob
#
# Responsável por enviar UMA notificação para UM evento específico.
# Coordena com o AgendaNotificationLog para evitar re-envios.
#
# Fluxo:
#   1. Carrega event, rule e account
#   2. Renderiza o template com os dados reais do paciente/evento
#   3. Para cada inbox configurada na regra (ou TODAS da conta se nenhuma configurada),
#      tenta encontrar/criar uma conversa ativa com o contato e envia a mensagem
#   4. Registra o resultado no AgendaNotificationLog
#
# Retry: 3 tentativas com backoff exponencial via Sidekiq defaults

class Agenda::SendNotificationJob < ApplicationJob
  queue_as :low

  def perform(account_id:, event_id:, rule_id:)
    account = Account.find(account_id)
    event   = account.agenda_events.find(event_id)
    rule    = account.agenda_notification_rules.find(rule_id)

    # Guard duplo: se já existe log, não envia de novo
    if AgendaNotificationLog.exists?(
      agenda_event_id: event.id,
      agenda_notification_rule_id: rule.id
    )
      Rails.logger.info("[Agenda::SendNotification] Já enviado: evento=#{event_id} regra=#{rule_id}")
      return
    end

    # Verifica se tem contato
    unless event.contact_id.present?
      log_result(account, event, rule, 'skipped', 'Evento sem contato vinculado')
      return
    end

    # Renderiza a mensagem substituindo variáveis
    service = Agenda::NotificationTemplateService.new(event: event, rule: rule)
    rendered_message = service.render

    # ── Resolve inboxes a usar ─────────────────────────────────────────────────
    # Se a regra tem inboxes configuradas, usa elas. Caso contrário, usa TODAS
    # as inboxes da conta que suportam envio de mensagens (WhatsApp, SMS, etc.)
    inbox_configs = resolve_inboxes(account, rule)

    if inbox_configs.empty?
      log_result(account, event, rule, 'skipped', 'Nenhuma inbox disponível na conta para envio')
      return
    end

    # Tenta enviar para cada inbox
    send_results = inbox_configs.map do |inbox_cfg|
      send_to_inbox(
        account: account,
        event: event,
        rule: rule,
        inbox_cfg: inbox_cfg,
        message: rendered_message
      )
    end

    # Determina status geral: sent se ao menos 1 funcionou
    final_status = send_results.any? { |r| r[:ok] } ? 'sent' : 'failed'
    error_msgs   = send_results.filter_map { |r| r[:error] }.join('; ')

    log_result(account, event, rule, final_status, error_msgs.presence)

  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[Agenda::SendNotification] RecordNotUnique ignorado: evento=#{event_id} regra=#{rule_id}")
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("[Agenda::SendNotification] Registro não encontrado: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[Agenda::SendNotification] Erro: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    raise # re-raise para retry do Sidekiq
  end

  private

  # ── Resolve inboxes ──────────────────────────────────────────────────────────

  def resolve_inboxes(account, rule)
    configured = Array(rule.inboxes).compact

    if configured.present?
      # Garante que os inbox_ids sejam inteiros e as inboxes existam
      configured.select { |cfg| cfg['inbox_id'].present? }
    else
      # Fallback: usa todas as inboxes que suportam envio ativo de mensagens
      Rails.logger.info("[Agenda::SendNotification] Regra #{rule.id} sem inboxes configuradas — usando todas da conta")
      account.inboxes
             .where(channel_type: %w[Channel::Whatsapp Channel::TwilioSms Channel::Sms Channel::Telegram])
             .map { |inbox| { 'inbox_id' => inbox.id, 'label' => inbox.name } }
    end
  end

  # ── Envio para uma inbox ─────────────────────────────────────────────────────

  def send_to_inbox(account:, event:, rule:, inbox_cfg:, message:)
    inbox_id = inbox_cfg['inbox_id'].to_i
    inbox    = account.inboxes.find_by(id: inbox_id)

    return { ok: false, error: "Inbox ##{inbox_id} não encontrada na conta #{account.id}" } unless inbox

    contact = event.contact
    return { ok: false, error: "Evento #{event.id} sem contato vinculado" } unless contact

    # Encontra ou cria contact_inbox (vínculo entre o contato e a inbox)
    contact_inbox = find_or_create_contact_inbox(inbox: inbox, contact: contact)
    return { ok: false, error: "Não foi possível criar contact_inbox para contato #{contact.id}" } unless contact_inbox

    # Reutiliza conversa aberta ou cria nova
    conversation = find_or_create_conversation(account: account, contact_inbox: contact_inbox)
    return { ok: false, error: 'Não foi possível obter conversa' } unless conversation

    # Cria a mensagem na conversa (fica visível no painel do Chatwoot)
    msg = conversation.messages.create!(
      content: message,
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      status: :sent,
      additional_attributes: {
        source: 'agenda_notification',
        agenda_event_id: event.id,
        agenda_notification_rule: rule.id
      }
    )

    Rails.logger.info("[Agenda::SendNotification] Mensagem ##{msg.id} criada na conversa ##{conversation.id}")

    # Dispara o envio real pelo canal
    # Removido: Chatwoot nativo já enfileira o SendReplyJob automaticamente
    # ao criar uma mensagem com message_type: :outgoing

    { ok: true }
  rescue StandardError => e
    Rails.logger.error("[Agenda::SendNotification] Falha no inbox #{inbox&.id}: #{e.class}: #{e.message}")
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  # ── Vínculo contact ↔ inbox ──────────────────────────────────────────────────

  def find_or_create_contact_inbox(inbox:, contact:)
    existing = contact.contact_inboxes.find_by(inbox: inbox)
    return existing if existing

    # Determina um source_id adequado (telefone para SMS/WhatsApp, email para outros)
    source_id = case inbox.channel_type
                when 'Channel::Whatsapp', 'Channel::TwilioSms', 'Channel::Sms'
                  contact.phone_number&.gsub(/\D/, '') || contact.id.to_s
                else
                  contact.identifier || contact.email || contact.id.to_s
                end

    ContactInbox.create!(
      contact_id: contact.id,
      inbox_id: inbox.id,
      source_id: (inbox.channel_type == 'Channel::Whatsapp' ? source_id : "#{source_id}_#{SecureRandom.hex(4)}")
    )
  rescue ActiveRecord::RecordNotUnique
    # Race condition: outro processo criou o registro
    contact.contact_inboxes.find_by(inbox: inbox)
  rescue StandardError => e
    Rails.logger.warn("[Agenda::SendNotification] Não foi possível criar contact_inbox: #{e.message}")
    nil
  end

  # ── Conversa ─────────────────────────────────────────────────────────────────

  def find_or_create_conversation(account:, contact_inbox:)
    # Reutiliza conversa aberta mais recente
    conversation = contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
    return conversation if conversation

    # Cria nova conversa vinculada ao contact_inbox
    account.conversations.create!(
      inbox_id: contact_inbox.inbox_id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: { source: 'agenda_notification' }
    )
  rescue StandardError => e
    Rails.logger.error("[Agenda::SendNotification] Falha ao criar conversa: #{e.message}")
    nil
  end

  # ── Helpers de log ───────────────────────────────────────────────────────────

  def log_result(account, event, rule, status, error_message = nil)
    AgendaNotificationLog.create!(
      account_id: account.id,
      agenda_event_id: event.id,
      agenda_notification_rule_id: rule.id,
      sent_at: Time.current,
      status: status,
      error_message: error_message
    )
    Rails.logger.info("[Agenda::SendNotification] Log criado: evento=#{event.id} regra=#{rule.id} status=#{status}#{if error_message
                                                                                                                      " error=#{error_message}"
                                                                                                                    end}")
  end
end
