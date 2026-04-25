class Webhooks::WhatsappQrController < ActionController::API
  def process_payload
    # Tenta encontrar por qualquer canal de WhatsApp que dê match no ID/Número (independente do provedor)
    search_number = params[:phone_number].to_s.gsub(/\D/, '')
    own_number_clean = params[:own_number].to_s.gsub(/\D/, '')

    channel = Channel::Whatsapp.where('phone_number LIKE ?', "%#{params[:phone_number]}%").first
    channel ||= Channel::Whatsapp.where('phone_number LIKE ?', "%#{search_number}%").first if search_number.present?

    # Se não achou, tenta pelo número real do remetente conectado (own_number)
    if !channel && params[:own_number].present?
      channel = Channel::Whatsapp.where('phone_number LIKE ?', "%#{params[:own_number]}%").first
      channel ||= Channel::Whatsapp.where('phone_number LIKE ?', "%#{own_number_clean}%").first if own_number_clean.present?
    end

    unless channel
      Rails.logger.warn("[WHATSAPP_QR] Canal não encontrado para: #{params[:phone_number]} (own: #{params[:own_number]})")
      render json: { error: 'Canal não encontrado' }, status: :not_found
      return
    end

    # SINCRONIZAÇÃO E CORREÇÃO: Garante que o provedor seja 'whatsapp_qr' para habilitar as funções do motor
    # e atualiza o phone_number para o número real do aparelho (own_number)
    update_attrs = {}
    update_attrs[:provider] = 'whatsapp_qr' if channel.provider != 'whatsapp_qr'
    update_attrs[:phone_number] = params[:own_number] if params[:own_number].present? && channel.phone_number != params[:own_number]
    
    if update_attrs.present?
       channel.update!(update_attrs)
       Rails.logger.info("[WHATSAPP_QR] Canal #{channel.id} atualizado: #{update_attrs.inspect}")
    end

    unless channel.account.active?
      render json: { error: 'Account inactive' }, status: :unprocessable_entity
      return
    end

    Rails.logger.info("[WHATSAPP_QR] Mensagem recebida para canal #{channel.id}: #{params.to_unsafe_hash.inspect}")

    Whatsapp::IncomingMessageQrService.new(
      inbox: channel.inbox,
      params: params.to_unsafe_hash.with_indifferent_access
    ).perform

    head :ok
  end
end
