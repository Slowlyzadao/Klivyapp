# MVP lançamento por voucher. Decide se a Bea pode responder uma conversa:
# no "modo voucher", ela SÓ atende quem chegou por um voucher — foto (imagem)
# ou um dos textos-gatilho do QR. Quem não chegou assim fica sem resposta.
#
# Uma vez ativada (mandou foto/gatilho), a conversa fica marcada
# (ConversationState.working_memory['voucher']) e segue respondendo nos
# próximos turnos por texto.
class AiAgent::Voucher::Gate
  def initialize(account:, conversation:, message:)
    @account = account
    @conversation = conversation
    @message = message
    @resolver = AiAgent::ConfigResolver.new(account)
  end

  def enabled?
    @resolver.voucher_mode?
  end

  # Pode responder? Já ativada antes OU está ativando agora (imagem/gatilho).
  def allowed?
    activated? || activating?
  end

  def activating?
    image? || trigger_match?
  end

  def image?
    @message.attachments.any? { |a| a.file_type.to_s == 'image' }
  end

  # Texto bate com algum gatilho do QR? Tolerante a caixa/acento/espaços.
  def trigger_match?
    msg = normalize(@message.content)
    return false if msg.blank?

    @resolver.voucher_triggers.any? { |t| (n = normalize(t)).present? && msg.include?(n) }
  end

  def activated?
    voucher_state['activated'] == true
  end

  # Marca a conversa como ativada por voucher (persiste o texto do voucher pra
  # referência). Merge defensivo — não pisa em outras chaves do working_memory.
  def mark_activated!(voucher_text: nil)
    mem = state.working_memory.is_a?(Hash) ? state.working_memory.dup : {}
    mem['voucher'] = { 'activated' => true, 'voucher_text' => voucher_text }.compact
    state.update!(working_memory: mem)
  end

  private

  def voucher_state
    wm = state.working_memory
    wm.is_a?(Hash) && wm['voucher'].is_a?(Hash) ? wm['voucher'] : {}
  end

  def state
    @state ||= AiAgent::ConversationState.for(account: @account, conversation_id: @conversation.id)
  end

  # downcase + remove acento + colapsa espaços. Aplicado igual nos dois lados,
  # então emoji (virado em '?') também casa simetricamente.
  def normalize(str)
    I18n.transliterate(str.to_s.downcase).gsub(/\s+/, ' ').strip
  end
end
