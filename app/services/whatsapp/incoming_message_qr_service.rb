# Serviço responsável por processar mensagens recebidas do motor WhatsApp QR (Baileys)
# Payload: { id, from, sender_jid, sender_name, text, timestamp, is_group, attachment }
# attachment: { url, mime_type, type, filename } — URL servida pelo bridge em localhost:3002
class Whatsapp::IncomingMessageQrService
  pattr_initialize [:inbox!, :params!]

  def perform
    message_data = params[:message]
    return unless message_data.present?

    # Extrai campos do payload
    raw_from    = message_data[:from].to_s
    sender_jid  = (message_data[:sender_jid] || message_data[:from]).to_s
    is_group    = message_data[:is_group]
    display_name = message_data[:sender_name] || sender_jid.split('@').first
    message_text = message_data[:text].presence
    message_id   = message_data[:id]
    timestamp    = message_data[:timestamp] || Time.now.to_i
    attachment_params = message_data[:attachment]
    group_name   = message_data[:group_name]
    is_from_me   = message_data[:from_me] == true
    sender_avatar_url = message_data[:sender_avatar_url].presence

    Rails.logger.info("[WHATSAPP_QR] Mensagem de #{sender_jid} (#{display_name}) | grupo=#{is_group} | from_me=#{is_from_me} | attachment=#{attachment_params&.dig(:type) || 'nenhum'}")

    # Normaliza JID do remetente -> número real
    phone_raw    = sender_jid.split('@').first.split(':').first
    phone_number = "+#{phone_raw}"
    group_id     = is_group ? raw_from.split('@').first : nil

    if is_group
      # Se for grupo, o contato representa o grupo inteiro
      contact_source_id = group_id
      contact_phone = nil # Grupos não têm número de telefone válido E164
      contact_name = group_name.presence || "Grupo #{group_id.to_s[-4..-1]}"
      contact_identifier = raw_from
    elsif is_from_me
      # Mensagem enviada pelo próprio celular → o contato é o DESTINATÁRIO (raw_from), não o remetente
      recipient_raw = raw_from.split('@').first.split(':').first
      recipient_name = message_data[:recipient_name].presence
      contact_source_id = recipient_raw
      contact_phone = "+#{recipient_raw}"
      # Usa o nome do destinatário que o bridge conseguiu obter, ou fallback para o número
      contact_name = recipient_name || "+#{recipient_raw}"
      contact_identifier = raw_from
    else
      # Mensagem recebida de outro contato → o contato é o REMETENTE
      # Proteção: se sender_jid ainda é LID (não resolvido pelo bridge), não usa como telefone
      is_lid = sender_jid.include?('@lid')
      contact_source_id = phone_raw
      contact_phone = is_lid ? nil : phone_number
      contact_name = display_name
      contact_identifier = sender_jid
    end

    # ─── ANTI-DUPLICAÇÃO DE CONTATOS ──────────────────────────────────────
    # Quando o WhatsApp manda um LID (ID interno) ao invés do número real,
    # o source_id e identifier mudam, criando contatos duplicados.
    # Aqui fazemos uma busca mais inteligente para reusar contatos existentes.
    contact_inbox = find_existing_contact_inbox(contact_source_id, contact_phone, contact_identifier, is_group)

    if contact_inbox.nil?
      # Não encontrou → usa o builder padrão para criar
      contact_inbox = ::ContactInboxWithContactBuilder.new(
        source_id: contact_source_id,
        inbox: inbox,
        contact_attributes: {
          name: contact_name,
          phone_number: contact_phone,
          identifier: contact_identifier
        }
      ).perform
    end

    @contact       = contact_inbox.contact
    @contact_inbox = contact_inbox

    # Garante que o identificador esteja preenchido para aparecer na interface
    @contact.update!(identifier: contact_identifier) if @contact.identifier.blank?

    # Atualiza o nome do grupo se ele chegar posteriormente
    if is_group && group_name.present? && @contact.name != group_name
      @contact.update!(name: group_name)
    end

    # Se o contato tem nome genérico (só número) e agora temos o nome real do WhatsApp, atualiza
    if !is_from_me && !is_group && display_name.present?
      current_name = @contact.name.to_s
      # Considera "genérico" se o nome começa com "+" (número de telefone) ou é igual ao phone_raw
      is_generic_name = current_name.start_with?('+') || current_name == phone_raw
      if is_generic_name && current_name != display_name
        @contact.update!(name: display_name)
        Rails.logger.info("[WHATSAPP_QR] 👤 Nome do contato atualizado: #{current_name} → #{display_name}")
      end
    end

    # Sincroniza avatar de perfil (1:1). Para grupos, o avatar do contato-grupo
    # vem do groupMetadata e o avatar individual será sincronizado mais abaixo
    # quando criamos `actual_sender`. AvatarFromUrlJob é idempotente, rate-limita
    # 1min e dedupe por hash da URL — seguro chamar sempre que tivermos URL.
    if sender_avatar_url.present? && !is_group
      Avatar::AvatarFromUrlJob.perform_later(@contact, sender_avatar_url)
    end

    # Cria/encontra conversa
    @conversation = find_or_create_conversation(group_id, is_from_me)

    # Evita mensagens duplicadas
    return if Message.find_by(source_id: message_id.to_s)

    # Em grupos: usamos o texto limpo, sem prefixo manual
    final_content = message_text

    # Identificar o remetente real se for um grupo
    actual_sender = @contact
    if is_group
      # Normaliza o phone_raw removendo prefixo "lid:" se existir
      # LID JIDs vêm como "lid:17734070984837@lid" ou "17734070984837:42@s.whatsapp.net"
      clean_phone_raw = phone_raw.gsub(/^lid:/, '')

      # Busca o contato existente por identifier OU por source_id (para LIDs)
      existing_individual = inbox.contacts.find_by(identifier: sender_jid)
      existing_individual ||= inbox.contact_inboxes.find_by(source_id: clean_phone_raw)&.contact

      # Determina o nome a usar:
      # Se o WhatsApp mandou vazio, preserva o nome que já temos no Chatwoot
      # Se não temos nenhum nome salvo, usa o phone_number como último recurso
      is_incoming_name_generic = display_name.blank?

      processed_sender_name = if is_incoming_name_generic && existing_individual.present? && existing_individual.name.present?
                                existing_individual.name
                              elsif is_incoming_name_generic
                                phone_number
                              else
                                display_name
                              end

      actual_sender_contact_inbox = ::ContactInboxWithContactBuilder.new(
        source_id: clean_phone_raw,
        inbox: inbox,
        contact_attributes: {
          name: processed_sender_name,
          phone_number: phone_number,
          identifier: sender_jid
        }
      ).perform
      
      actual_sender = actual_sender_contact_inbox.contact

      # Se o nome continua genérico e temos um nome melhor, atualize
      if !is_incoming_name_generic && actual_sender.name != display_name
        actual_sender.update!(name: display_name)
      end

      # Avatar do participante individual do grupo (não do grupo em si).
      if sender_avatar_url.present?
        Avatar::AvatarFromUrlJob.perform_later(actual_sender, sender_avatar_url)
      end
    end

    # Para mensagens from_me: tipo outgoing
    msg_type   = is_from_me ? :outgoing : :incoming
    msg_status = is_from_me ? :delivered : :sent
    # Em grupos from_me, precisamos de um sender válido para o ActionCable renderizar;
    # Para privado from_me, sender nil representa o agente/conta.
    msg_sender = if is_from_me && !is_group
                   nil
                 elsif is_from_me && is_group
                   # Usa o primeiro agente disponível como sender, para que a mensagem renderize
                   inbox.inbox_members.first&.user
                 else
                   actual_sender
                 end

    # Cria a mensagem em memória Primeiro para não disparar o ActionCable com arquivo vazio
    message = @conversation.messages.build(
      content: final_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: msg_type,
      status: msg_status,
      sender: msg_sender,
      source_id: message_id.to_s,
      content_type: attachment_params&.dig('type') == 'sticker' ? 'sticker' : nil,
      content_attributes: { is_group: is_group }.merge(is_from_me ? { from_phone: true } : {}),
      created_at: Time.zone.at(timestamp)
    )

    # Baixa e anexa mídia se presente
    if attachment_params.present? && attachment_params[:url].present?
      attach_media_from_url(message, attachment_params)
    end

    # Agora sim salva no banco conectadinho, assim o ActionCable voa perfeito pro Frontend!
    message.save!

    Rails.logger.info("[WHATSAPP_QR] Mensagem criada com sucesso na conversa #{@conversation.id}")
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP_QR] Erro ao processar mensagem: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  end

  private

  # Busca inteligente para evitar duplicação de contatos.
  # O WhatsApp pode enviar o mesmo remetente com JIDs diferentes:
  # - Número real: "5511971724960@s.whatsapp.net"
  # - LID (ID interno): "17734070984837@lid"
  # - Com device suffix: "5511971724960:42@s.whatsapp.net"
  # Também trata grupos, que podem chegar com o mesmo group_id mas criar duplicatas.
  def find_existing_contact_inbox(source_id, phone_number, identifier, is_group)
    # Para grupos: busca apenas por source_id (group_id) e identifier (raw_from)
    if is_group
      ci = inbox.contact_inboxes.find_by(source_id: source_id)
      if ci
        Rails.logger.debug "[WHATSAPP_QR] Anti-dup grupo: encontrado por source_id=#{source_id}"
        return ci
      end

      if identifier.present?
        contact = inbox.account.contacts.find_by(identifier: identifier)
        if contact
          ci = contact.contact_inboxes.find_by(inbox_id: inbox.id)
          if ci
            Rails.logger.info "[WHATSAPP_QR] Anti-dup grupo: encontrado por identifier=#{identifier}"
            return ci
          end
        end
      end

      return nil
    end

    # 1. Busca direta por source_id (mais rápido)
    ci = inbox.contact_inboxes.find_by(source_id: source_id)
    if ci
      Rails.logger.debug "[WHATSAPP_QR] Anti-dup: encontrado por source_id=#{source_id}"
      return ci
    end

    # 2. Busca pelo identifier (ex: "5511971724960@s.whatsapp.net")
    if identifier.present?
      contact = inbox.account.contacts.find_by(identifier: identifier)
      if contact
        ci = contact.contact_inboxes.find_by(inbox_id: inbox.id)
        if ci
          Rails.logger.info "[WHATSAPP_QR] Anti-dup: encontrado por identifier=#{identifier}"
          return ci
        end
      end
    end

    # 3. Busca pelo phone_number ("+5511971724960")
    if phone_number.present?
      contact = inbox.account.contacts.find_by(phone_number: phone_number)
      if contact
        ci = contact.contact_inboxes.find_by(inbox_id: inbox.id)
        if ci
          Rails.logger.info "[WHATSAPP_QR] Anti-dup: encontrado por phone=#{phone_number}"
          return ci
        end
      end
    end

    # 4. Para LIDs: busca pelo número extraído como parte de identifier existente
    # Se source_id parece um número de telefone (só dígitos, 10-15 chars), tenta como @s.whatsapp.net
    if source_id.present? && source_id.match?(/\A\d{10,15}\z/)
      jid_identifier = "#{source_id}@s.whatsapp.net"
      contact = inbox.account.contacts.find_by(identifier: jid_identifier)
      if contact
        ci = contact.contact_inboxes.find_by(inbox_id: inbox.id)
        if ci
          Rails.logger.info "[WHATSAPP_QR] Anti-dup: encontrado por JID inferido=#{jid_identifier}"
          return ci
        end
      end
    end

    # 5. Busca reversa: se o identifier é LID, tenta encontrar contato com phone que bata
    if identifier&.include?('@lid') && source_id.present?
      ci = inbox.contact_inboxes
                .joins(:contact)
                .where('contacts.phone_number IS NOT NULL')
                .where('contacts.phone_number != ?', '')
                .find_by(source_id: source_id)
      if ci
        Rails.logger.info "[WHATSAPP_QR] Anti-dup: LID=#{identifier} mapeado para contato #{ci.contact.name}"
        return ci
      end
    end

    nil
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP_QR] Anti-dup: erro na busca (prosseguindo com criação): #{e.message}"
    nil
  end

  def find_or_create_conversation(group_id, from_me = false)
    if group_id
      # Para grupos: uma conversa única por group_id no inbox
      # Busca amplamente (não só pelo contact_inbox) para evitar duplicatas
      # mesmo quando o contact_inbox muda entre mensagens
      existing = Conversation
                   .where(inbox_id: inbox.id, contact_id: @contact.id)
                   .where("additional_attributes->>'group_id' = ?", group_id)
                   .order(created_at: :asc)
                   .first
      return existing if existing

      # Proteção contra race condition: tenta criar, ignora se já existe
      begin
        Conversation.create!(
          account_id: inbox.account_id,
          inbox_id: inbox.id,
          contact_id: @contact.id,
          contact_inbox_id: @contact_inbox.id,
          additional_attributes: { 'group_id' => group_id }
        )
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Outro processo criou no mesmo instante → busca e retorna a existente
        Conversation
          .where(inbox_id: inbox.id, contact_id: @contact.id)
          .where("additional_attributes->>'group_id' = ?", group_id)
          .order(created_at: :asc)
          .first
      end
    else
      # Para diretos: conversa aberta/pendente existente
      existing = if from_me
                   @contact_inbox.conversations.order(created_at: :desc).first
                 else
                   @contact_inbox.conversations.where.not(status: :resolved).last
                 end
      return existing if existing

      Conversation.create!(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        contact_id: @contact.id,
        contact_inbox_id: @contact_inbox.id,
        additional_attributes: {}
      )
    end
  end

  # Baixa o arquivo da URL temporária do bridge e cria um Attachment em memória no Chatwoot
  def attach_media_from_url(message, attachment_params)
    url        = attachment_params[:url].to_s
    # Normaliza MIME type: "audio/ogg; codecs=opus" → "audio/ogg"
    mime_type  = attachment_params[:mime_type].to_s.split(';').first.strip
    filename   = attachment_params[:filename].to_s.presence || 'attachment'
    media_type = attachment_params[:type].to_s

    file_type = case media_type
                when 'image', 'sticker' then :image
                when 'audio'            then :audio
                when 'video'            then :video
                else                         :file
                end

    # Baixa o arquivo do bridge como dados binários puros
    uri      = URI.parse(url)
    http     = Net::HTTP.new(uri.host, uri.port)
    request  = Net::HTTP::Get.new(uri)
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[WHATSAPP_QR] Falha ao baixar mídia: HTTP #{response.code} → #{url}")
      return
    end

    # IMPORTANTE: força encoding binário para não corromper dados de imagem/áudio
    binary = response.body.dup.force_encoding('ASCII-8BIT')

    # Usa SEMPRE o mime_type do payload (não o do HTTP response, que pode ser errado)
    stored_mime = mime_type
    stored_mime = 'audio/ogg' if media_type == 'audio' && mime_type.start_with?('audio/')
    stored_mime = 'image/webp' if media_type == 'sticker'

    # Anexa o arquivo NA MEMÓRIA através de build.
    # O ActiveStorage / Chatwoot cuidará do upload físico quando "message.save!" for executado.
    message.attachments.new(
      account_id: inbox.account_id,
      file_type: file_type,
      extension: media_type == 'sticker' ? 'webp' : nil,
      meta: media_type.to_s == 'sticker' ? { is_sticker: true } : {},
      file: {
        io: StringIO.new(binary),
        filename: filename,
        content_type: stored_mime
      }
    )

    Rails.logger.info("[WHATSAPP_QR] Mídia #{filename} preparada na memória com sucesso (#{stored_mime})")
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP_QR] Falha ao preparar mídia em memória: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
  end
end
