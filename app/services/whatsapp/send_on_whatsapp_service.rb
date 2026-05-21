class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    is_whatsapp_qr = channel.provider == 'whatsapp_qr'

    # WhatsApp QR (Baileys) não suporta templates — SEMPRE envia como mensagem de sessão.
    # Sem isso, payloads com template_params fazem a mensagem ficar presa como "sent" eternamente.
    if is_whatsapp_qr
      send_session_message
      return
    end

    # Para provedores oficiais (Cloud API, 360Dialog): usa template se necessário
    should_send_template = template_params.present? || !message.conversation.can_reply?

    if should_send_template
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_session_message
    message_id = channel.send_message(message.conversation.contact_inbox.source_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
