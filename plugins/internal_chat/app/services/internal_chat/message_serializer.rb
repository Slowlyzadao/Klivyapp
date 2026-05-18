module InternalChat
  # Serializer leve. Não usamos jbuilder views aqui pra manter o plugin
  # autocontido (mesma decisão das controllers — render :json direto).
  class MessageSerializer
    def initialize(message, replied_cache: nil, current_user: nil, favorited_ids: nil)
      @message = message
      @replied_cache = replied_cache
      @current_user = current_user
      # Cache opcional de IDs já favoritados (set/array) pra evitar N+1 em
      # listagens grandes; quando não passado, fallback consulta direto.
      @favorited_ids = favorited_ids
    end

    def as_json
      {
        id: @message.id,
        # account_id é obrigatório no payload de cable events: o
        # ActionCableConnector do core filtra eventos por account_id antes de
        # despachar para os handlers.
        account_id: @message.room.account_id,
        room_id: @message.room_id,
        sender: build_sender,
        content: @message.content,
        content_type: @message.content_type,
        content_attributes: @message.content_attributes,
        in_reply_to: @message.in_reply_to_id,
        in_reply_to_message: serialize_replied,
        mentioned_user_ids: Array(@message.content_attributes['mentioned_user_ids']).map(&:to_i),
        mentioned_ai_agent_ids: Array(@message.content_attributes['mentioned_ai_agent_ids']).map(&:to_i),
        edited_at: @message.edited_at,
        deleted_at: @message.deleted_at,
        created_at: @message.created_at,
        attachments: @message.attachments.map { |a| attachment_payload(a) },
        sticker: serialize_sticker,
        is_favorited: favorited_for_current_user?,
        reactions: reactions_payload,
      }
    end

    private

    # Agrega `@message.reactions` por emoji, retornando contagem + flag
    # "esta reação fui eu". Se :reactions vier preloaded (includes no index),
    # não tem N+1 — vira só array.group_by em memória.
    def reactions_payload
      return [] unless @message.reactions.any?

      by_emoji = @message.reactions.group_by(&:emoji)
      by_emoji.map do |emoji, list|
        {
          emoji: emoji,
          count: list.size,
          by_me: @current_user ? list.any? { |r| r.user_id == @current_user.id } : false,
          user_ids: list.map(&:user_id),
        }
      end.sort_by { |r| -r[:count] }
    end

    def favorited_for_current_user?
      return false unless @current_user

      if @favorited_ids
        @favorited_ids.include?(@message.id)
      else
        InternalChat::MessageFavorite.exists?(user_id: @current_user.id, message_id: @message.id)
      end
    end

    def build_sender
      if @message.sender
        sender_payload(@message.sender)
      elsif @message.sender_ai_agent_id
        ai_sender_payload
      end
    end

    def serialize_replied
      id = @message.in_reply_to_id
      return nil if id.blank?

      replied = @replied_cache ? @replied_cache[id.to_i] : @message.room.messages.find_by(id: id)
      return nil unless replied

      {
        id: replied.id,
        sender_name: replied.sender&.available_name || (replied.sender_ai_agent_id ? InternalChat::BeaResolver::DISPLAY_LABEL : nil),
        content_type: replied.content_type,
        content_preview: (replied.content || '')[0, 140],
        deleted_at: replied.deleted_at,
        first_attachment_type: replied.attachments.first&.file_type,
        thumb_url: replied_thumb_url(replied),
      }
    end

    # URL pra miniatura da mensagem citada — sticker.image_url se for figurinha,
    # ou thumb da primeira imagem anexada. Outros tipos (vídeo, áudio, arquivo)
    # não têm thumb pronta no payload, retornam nil.
    def replied_thumb_url(replied)
      return replied.sticker.image_url if replied.sticker_id && replied.sticker

      first = replied.attachments.first
      return nil unless first&.file_type == 'image'

      first.thumb_url.presence || first.file_url
    end

    def sender_payload(user)
      {
        id: user.id,
        name: user.available_name,
        avatar_url: user.respond_to?(:avatar_url) ? user.avatar_url : nil,
        is_ai: false,
      }
    end

    def ai_sender_payload
      {
        id: @message.sender_ai_agent_id,
        name: InternalChat::BeaResolver::DISPLAY_LABEL,
        avatar_url: nil,
        is_ai: true,
      }
    end

    def serialize_sticker
      return nil unless @message.sticker_id

      sticker = @message.sticker
      return nil unless sticker

      {
        id: sticker.id,
        image_url: sticker.image_url,
        width: sticker.width,
        height: sticker.height,
      }
    end

    def attachment_payload(att)
      {
        id: att.id,
        file_type: att.file_type,
        file_name: att.file_name,
        content_type: att.content_type,
        file_size: att.file_size,
        file_url: att.file_url,
        thumb_url: att.file_type == 'image' ? att.thumb_url : nil,
        download_url: attachment_download_url(att),
      }
    end

    # Pra WebP, rota custom converte de volta pra JPG/PNG na hora do download.
    # Pra outros tipos (vídeo, PDF, áudio), URL direta do ActiveStorage.
    def attachment_download_url(att)
      return att.file_url unless att.content_type == 'image/webp'
      return att.file_url unless @message.room

      "/api/v1/accounts/#{@message.room.account_id}/internal_chat/rooms/#{@message.room_id}/attachments/#{att.id}/download"
    end
  end
end
