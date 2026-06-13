# Envia o status de presença ("digitando..." / "parou") pro WhatsApp via
# bridge Baileys. Best-effort com timeout curto — uma bridge lenta NUNCA
# deve atrasar nem quebrar o pipeline de resposta.
#
# Usada em dois pontos:
#   - MessageListener: dispara `composing` na CHEGADA da mensagem (<1s),
#     antes do debounce, pra Bea parecer responsiva na hora.
#   - ChatResponseJob: dispara no início + MANTÉM VIVO com heartbeat (o
#     WhatsApp limpa o "digitando" sozinho em ~10s), e `paused` ao terminar.
#
# Só atua em inbox `whatsapp_qr` (Baileys). Outros canais (cloud/360)
# precisariam da própria integração.
class AiAgent::WhatsappPresence
  BRIDGE_URL = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }

  COMPOSING = 'composing'
  PAUSED = 'paused'

  # Resolve {inbox_id, phone} a partir da conversa — só pra whatsapp_qr.
  # Retorna nil (no-op) pra qualquer outro canal ou sem telefone. Devolver
  # primitivos permite usar o resultado numa thread sem tocar no ActiveRecord.
  def self.target_for(conversation)
    inbox = conversation&.inbox
    return nil unless inbox&.channel_type == 'Channel::Whatsapp'
    return nil unless inbox.channel.respond_to?(:provider) && inbox.channel.provider.to_s == 'whatsapp_qr'

    phone = conversation.contact&.phone_number.to_s.gsub(/\D/, '')
    return nil if phone.empty?

    { inbox_id: inbox.id, phone: phone }
  end

  # Envia o estado pro bridge. `target` é o hash de target_for (ou nil).
  def self.push(target, state)
    return if target.nil?

    uri = URI("#{BRIDGE_URL}/sessions/#{target[:inbox_id]}/presence")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 3
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    req.body = { to: "#{target[:phone]}@s.whatsapp.net", state: state }.to_json
    http.request(req)
  rescue StandardError => e
    Rails.logger.debug { "[AiAgent::WhatsappPresence] (#{state}) skipped: #{e.message}" }
  end

  # Atalho: dispara "digitando..." imediatamente pra uma conversa.
  def self.composing(conversation)
    push(target_for(conversation), COMPOSING)
  end
end
