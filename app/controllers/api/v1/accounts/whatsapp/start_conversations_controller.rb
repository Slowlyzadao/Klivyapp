class Api::V1::Accounts::Whatsapp::StartConversationsController < Api::V1::Accounts::BaseController
  # POST /api/v1/accounts/:account_id/whatsapp/start_conversation
  # Body: { phone_number: "11916019363" | "+5511916019363", inbox_id?: 12 }
  #
  # Fluxo:
  # 1. Normaliza o número (assume +55 se digits < 12)
  # 2. Resolve a inbox WhatsApp QR (parâmetro `inbox_id` ou primeira conectada)
  # 3. Pergunta ao bridge se o número TEM WhatsApp
  # 4. Se sim → cria/reusa contato e conversa, retorna `{ conversation_id, ... }`
  # 5. Se não → 404 com `error: 'NUMBER_NOT_ON_WHATSAPP'`
  def create
    phone_number = normalize_phone(params[:phone_number])
    return render_error(:bad_request, 'INVALID_PHONE') if phone_number.blank?

    inbox = resolve_inbox
    return render_error(:not_found, 'NO_WHATSAPP_INBOX') if inbox.nil?

    # Gate: usa `reply?` (não `create?`) — o default `ApplicationPolicy#create?`
    # é hardcoded `false`, e quem pode responder mensagens (admin, bot, ou
    # Klivy can(:chat, :reply)) também deve poder iniciar uma nova conversa.
    return render json: { error: 'FORBIDDEN' }, status: :forbidden unless ConversationPolicy.new(pundit_user, Conversation.new(inbox: inbox)).reply?

    bridge_check = check_number_on_whatsapp(inbox.id, phone_number)

    case bridge_check[:status]
    when :exists
      conversation = find_or_create_conversation(inbox, phone_number)
      render json: {
        success: true,
        conversation_id: conversation.display_id,
        contact_id: conversation.contact_id,
        inbox_id: inbox.id,
        account_id: Current.account.id
      }
    when :not_exists
      render_error(:not_found, 'NUMBER_NOT_ON_WHATSAPP')
    when :inbox_disconnected
      render_error(:service_unavailable, 'INBOX_DISCONNECTED')
    else
      render_error(:bad_gateway, 'BRIDGE_ERROR', bridge_check[:message])
    end
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP_START_CONVERSATION] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render_error(:internal_server_error, 'UNEXPECTED', e.message)
  end

  private

  def render_error(status, code, message = nil)
    render json: { success: false, error: code, message: message }.compact, status: status
  end

  # Aceita "11 91601-9363", "(11) 91601-9363", "+5511916019363", "5511916019363".
  # Se digits < 12, assume Brasil (+55). Retorna E.164 sem o `+`.
  def normalize_phone(input)
    return nil if input.blank?

    digits = input.to_s.gsub(/\D/, '')
    return nil if digits.length < 8 || digits.length > 15

    digits = "55#{digits}" if digits.length < 12
    digits
  end

  # Usa inbox passado pelo cliente, ou pega a primeira WhatsApp QR da conta.
  # Inbox#channel é polymorphic (não tem association `:channel_whatsapp`),
  # então filtramos por `channel_type` e depois consultamos o provider via
  # JOIN explícito na tabela `channel_whatsapp`.
  def resolve_inbox
    base = Current.account.inboxes.where(channel_type: 'Channel::Whatsapp')

    if params[:inbox_id].present?
      base.find_by(id: params[:inbox_id])
    else
      base.joins(
        'INNER JOIN channel_whatsapp ON channel_whatsapp.id = inboxes.channel_id'
      ).where('channel_whatsapp.provider = ?', 'whatsapp_qr').first
    end
  end

  def check_number_on_whatsapp(inbox_id, phone_number)
    bridge_url = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }
    uri = URI("#{bridge_url}/sessions/#{inbox_id}/check_number")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 12
    http.open_timeout = 5
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = { phone_number: phone_number }.to_json
    response = http.request(request)

    if response.code == '503'
      { status: :inbox_disconnected }
    elsif response.is_a?(Net::HTTPSuccess)
      body = JSON.parse(response.body)
      body['exists'] ? { status: :exists, jid: body['jid'] } : { status: :not_exists }
    else
      { status: :bridge_error, message: response.body }
    end
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP_START_CONVERSATION] check_number falhou: #{e.message}")
    { status: :bridge_error, message: e.message }
  end

  # Reusa contato/conversa se já existirem. Cria via builders padrão se não.
  def find_or_create_conversation(inbox, phone_number)
    e164 = "+#{phone_number}"

    # Reusa contact_inbox se já existe (mesmo source_id)
    contact_inbox = inbox.contact_inboxes.find_by(source_id: phone_number)
    contact_inbox ||= ::ContactInboxWithContactBuilder.new(
      source_id: phone_number,
      inbox: inbox,
      contact_attributes: {
        name: e164,
        phone_number: e164,
        identifier: "#{phone_number}@s.whatsapp.net"
      }
    ).perform

    contact = contact_inbox.contact

    # Reusa conversa aberta se houver
    open_conversation = contact_inbox.conversations
                                     .where.not(status: :resolved)
                                     .order(created_at: :desc)
                                     .first
    return open_conversation if open_conversation

    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: { initiated_by: 'agent' }
    )
  end
end
