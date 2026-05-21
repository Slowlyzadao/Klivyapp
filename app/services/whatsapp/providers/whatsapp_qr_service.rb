# Serviço de envio de mensagens via motor WhatsApp QR (Baileys)
# Conecta o Chatwoot ao motor Node.js em http://localhost:3002
# Suporta múltiplas instâncias via /sessions/:inbox_id/
class Whatsapp::Providers::WhatsappQrService < Whatsapp::Providers::BaseService
  # Aceita ambas as env vars para compatibilidade entre ambientes
  BRIDGE_URL = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }

  def send_message(phone_number, message)
    if message.attachments.present?
      send_attachment_message(phone_number, message)
    else
      send_text_message(phone_number, message.outgoing_content, message)
    end
  end

  def send_template(_phone_number, _template_info, _message)
    nil
  end

  def sync_templates
    true
  end

  def validate_provider_config?
    true
  end

  def media_url(_media_id)
    nil
  end

  def api_headers
    {}
  end

  def send_text_message(phone_number, text, message_obj = nil)
    payload = {
      to: determine_recipient(message_obj, phone_number),
      type: 'text',
      text: text
    }
    post_to_bridge('/send', payload, message_obj)
  end

  private

  # Retorna o inbox_id (ID da Inbox) para essa conversa
  # IMPORTANTE: O bridge multi-instância indexa sessões por INBOX ID, não channel ID!
  # Channel::Whatsapp.id ≠ Inbox.id — confundir os dois fazia o envio ir pra sessão errada
  def inbox_id_for(message)
    message&.conversation&.inbox&.id
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP_QR] Falha ao obter inbox_id: #{e.message}"
    nil
  end

  def determine_recipient(message, phone_number)
    # 1. Se o contato da conversa for explicitamente um grupo (@g.us no identifier)
    if message&.conversation&.contact&.identifier&.end_with?('@g.us')
      recipient = message.conversation.contact.identifier
      Rails.logger.info "[WHATSAPP_QR] determine_recipient: Grupo (pelo identifier) → #{recipient}"
      return recipient
    end

    # 2. Se houver o atributo group_id na conversa (fallback)
    if message&.conversation&.additional_attributes&.dig('group_id').present?
      recipient = message.conversation.contact.identifier
      Rails.logger.info "[WHATSAPP_QR] determine_recipient: Grupo (pelo group_id) → #{recipient}"
      return recipient
    end

    # 3. Caso contrário, envio privado normal
    recipient = "#{clean_phone(phone_number)}@s.whatsapp.net"
    Rails.logger.info "[WHATSAPP_QR] determine_recipient: Privado → #{recipient}"
    recipient
  end

  def clean_phone(phone_number)
    phone_number.to_s.gsub(/\D/, '')
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    file_type  = attachment.file_type.to_s

    type = case file_type
           when 'image'    then 'image'
           when 'audio'    then 'audio'
           when 'video'    then 'video'
           else                 'document'
           end

    # Garante IPv4 puro (127.0.0.1) na URL para evitar que o Node.js 18+ no macOS
    # resolva 'localhost' como IPv6 (::1) e o Rails rejeite a conexão silenciosamente
    download_url = attachment.download_url.to_s
                             .gsub('http://0.0.0.0:', 'http://127.0.0.1:')
                             .gsub('http://localhost:', 'http://127.0.0.1:')

    recipient = determine_recipient(message, phone_number)
    Rails.logger.info "[WHATSAPP_QR] send_attachment_message: tipo=#{type}, para=#{recipient}, url=#{download_url}"

    payload = {
      to: recipient,
      type: type,
      url: download_url,
      filename: attachment.file.filename.to_s,
      caption: message.outgoing_content.presence
    }
    post_to_bridge('/send', payload, message)
  end

  def post_to_bridge(path, payload, message = nil)
    # Usar o inbox_id como identificador da sessão no bridge
    iid = inbox_id_for(message)

    if iid.nil?
      Rails.logger.error '[WHATSAPP_QR] Não foi possível determinar inbox_id — mensagem não enviada.'
      mark_failed(message, 'Inbox ID não encontrado para a conversa')
      return nil
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Endpoint multi-instância: /sessions/:inbox_id/:path
    uri  = URI("#{BRIDGE_URL}/sessions/#{iid}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    # Áudio/vídeo precisam de mais tempo (download + conversão ffmpeg)
    http.read_timeout = %w[audio video].include?(payload[:type]) ? 25 : 15

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    Rails.logger.info "[WHATSAPP_QR] POST #{uri}: tipo=#{payload[:type]}, para=#{payload[:to]}"

    response = http.request(request)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    if response.code.to_i == 200
      result = JSON.parse(response.body)
      if result['success']
        wa_id = result['id'].to_s
        message&.update!(status: :delivered, source_id: wa_id)
        Rails.logger.info "[WHATSAPP_QR] ✅ Entregue em #{elapsed_ms}ms: wa_id=#{wa_id}"
        return wa_id
      else
        error_msg = result['error'] || result.inspect
        Rails.logger.error "[WHATSAPP_QR] Bridge retornou falha (#{elapsed_ms}ms): #{error_msg}"
        mark_failed(message, "Bridge: #{error_msg}")
        return nil
      end
    else
      error_body = response.body.to_s.force_encoding('UTF-8').truncate(200)
      Rails.logger.error "[WHATSAPP_QR] Erro #{response.code} (#{elapsed_ms}ms): #{error_body}"
      mark_failed(message, "HTTP #{response.code}: #{error_body}")
      return nil
    end

  rescue Errno::ECONNREFUSED => e
    Rails.logger.error "[WHATSAPP_QR] Bridge indisponível (ECONNREFUSED): #{BRIDGE_URL} — #{e.message}"
    mark_failed(message, "WhatsApp Bridge indisponível em #{BRIDGE_URL}")
    return nil
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[WHATSAPP_QR] Timeout na conexão com o motor: #{e.message}"
    mark_failed(message, "Timeout ao conectar com WhatsApp Bridge: #{e.class.name}")
    return nil
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_QR] Falha na conexão com o motor: #{e.class.name} — #{e.message}"
    mark_failed(message, "Erro interno: #{e.class.name} — #{e.message.truncate(150)}")
    return nil
  end

  # Marca a mensagem como falha com erro descritivo para o UI exibir
  def mark_failed(message, error_description)
    return unless message

    message.update!(status: :failed, external_error: error_description)
    Rails.logger.warn "[WHATSAPP_QR] ❌ Mensagem #{message.id} marcada como failed: #{error_description}"
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_QR] Falha ao marcar mensagem como failed: #{e.message}"
  end
end
