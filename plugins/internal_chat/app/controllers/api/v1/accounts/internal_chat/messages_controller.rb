class Api::V1::Accounts::InternalChat::MessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_room
  before_action :fetch_message, only: [:update, :destroy, :favorite, :unfavorite, :react, :unreact]
  before_action :authorize_room_access

  def index
    scope = @room.messages.visible.includes(:sender, :attachments, :sticker, :reactions)
    scope = scope.where('id < ?', params[:before_id]) if params[:before_id].present?
    messages = scope.order(id: :desc).limit(page_size).reverse

    # Pré-busca mensagens citadas em batch (1 query) pra evitar N+1.
    reply_ids = messages.map { |m| m.in_reply_to_id&.to_i }.compact.uniq
    replied_cache = if reply_ids.any?
                      @room.messages.where(id: reply_ids)
                           .includes(:sender, :attachments)
                           .index_by(&:id)
                    else
                      {}
                    end

    favorited_ids = current_user_favorited_ids(messages.map(&:id))

    render json: {
      data: messages.map do |m|
        InternalChat::MessageSerializer.new(
          m,
          replied_cache: replied_cache,
          current_user: Current.user,
          favorited_ids: favorited_ids,
        ).as_json
      end,
    }
  end

  def create
    message = InternalChat::MessageDispatcher.call(
      room: @room,
      sender: Current.user,
      content: message_params[:content],
      content_attributes: parsed_content_attributes,
      attachments: webp_converted_attachments,
      sticker_id: resolved_sticker_id,
    )
    # RT-7: mark-read-by-sender agora vive no MessageDispatcher (single
    # source of truth). Controller não duplica mais a atualização.
    render json: { data: InternalChat::MessageSerializer.new(message, current_user: Current.user).as_json }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  EDIT_WINDOW = 5.minutes

  def update
    return head :forbidden unless @message.sender_user_id == Current.user.id
    # FE-16/17 (auditoria 2026-05-18): strings PT-BR migradas pra
    # `config/locales/pt_BR.yml`. Pattern incremental — controller é o
    # primeiro vertical migrado.
    return render(json: { error: I18n.t('internal_chat.controllers.messages.deleted_cannot_edit') }, status: :unprocessable_entity) if @message.deleted_at?
    return render(json: { error: I18n.t('internal_chat.controllers.messages.edit_window_expired') }, status: :unprocessable_entity) if @message.created_at < EDIT_WINDOW.ago
    return render(json: { error: I18n.t('internal_chat.controllers.messages.only_text_editable') }, status: :unprocessable_entity) if @message.content_type != 'text'

    @message.update!(
      content: message_params[:content],
      edited_at: Time.current,
    )
    broadcast_message_change(@message)
    render json: { data: InternalChat::MessageSerializer.new(@message, current_user: Current.user).as_json }
  end

  def destroy
    return head :forbidden unless can_delete?(@message)

    @message.soft_delete!
    broadcast_message_change(@message)
    render json: { data: InternalChat::MessageSerializer.new(@message, current_user: Current.user).as_json }
  end

  # Marca mensagem como favorita do usuário atual. Idempotente — repetir não
  # cria duplicata por causa do unique index (user_id, message_id).
  def favorite
    return head :forbidden if @message.deleted_at?

    InternalChat::MessageFavorite.find_or_create_by!(
      user_id: Current.user.id,
      message_id: @message.id,
    ) do |f|
      f.account_id = @room.account_id
      f.room_id = @room.id
    end
    render json: { data: { id: @message.id, is_favorited: true } }
  end

  def unfavorite
    InternalChat::MessageFavorite.where(user_id: Current.user.id, message_id: @message.id).delete_all
    render json: { data: { id: @message.id, is_favorited: false } }
  end

  # Reage à mensagem com um emoji. Trocar de emoji vira UPDATE da mesma linha
  # (uma reação por usuário por mensagem, estilo WhatsApp). Broadcast atualiza
  # todos os membros da sala via cable, e cada um recebe seu próprio `by_me`.
  def react
    return head :forbidden if @message.deleted_at?

    emoji = params[:emoji].to_s.strip
    return render(json: { error: I18n.t('internal_chat.controllers.messages.emoji_required') }, status: :unprocessable_entity) if emoji.blank?
    return render(json: { error: I18n.t('internal_chat.controllers.messages.emoji_too_long') }, status: :unprocessable_entity) if emoji.length > 16

    reaction = InternalChat::MessageReaction.find_or_initialize_by(
      user_id: Current.user.id,
      message_id: @message.id,
    )
    reaction.assign_attributes(
      emoji: emoji,
      account_id: @room.account_id,
      room_id: @room.id,
    )
    reaction.save!

    broadcast_message_change(@message)
    render json: { data: InternalChat::MessageSerializer.new(@message.reload, current_user: Current.user).as_json }
  end

  def unreact
    InternalChat::MessageReaction.where(user_id: Current.user.id, message_id: @message.id).delete_all

    broadcast_message_change(@message)
    render json: { data: InternalChat::MessageSerializer.new(@message.reload, current_user: Current.user).as_json }
  end

  # Lista mensagens favoritadas pelo usuário nesta sala, mais recentes primeiro.
  #
  # PERF-16 (auditoria 2026-05-18): paginação opt-in. Antes era limit fixo
  # 200 sem como acessar favoritos antigos. Agora `?page=N&per_page=M` —
  # default mantém 200 (backwards-compatible com chamadas existentes).
  FAVORITES_PER_PAGE_DEFAULT = 200
  FAVORITES_PER_PAGE_MAX = 200

  def favorites
    page = (params[:page].presence || 1).to_i.clamp(1, 10_000)
    per_page = (params[:per_page].presence || FAVORITES_PER_PAGE_DEFAULT)
               .to_i.clamp(1, FAVORITES_PER_PAGE_MAX)
    offset = (page - 1) * per_page

    base = InternalChat::MessageFavorite
           .where(user_id: Current.user.id, room_id: @room.id)
    total = base.count
    fav_scope = base.order(created_at: :desc)
                    .offset(offset)
                    .limit(per_page)
    message_ids = fav_scope.pluck(:message_id)
    if message_ids.empty?
      return render(json: { data: [], meta: { page: page, per_page: per_page, total: total } })
    end

    messages = @room.messages
                    .where(id: message_ids)
                    .includes(:sender, :attachments, :sticker)
                    .index_by(&:id)
    ordered = message_ids.map { |id| messages[id] }.compact

    render json: {
      data: ordered.map do |m|
        InternalChat::MessageSerializer.new(
          m,
          current_user: Current.user,
          favorited_ids: message_ids,
        ).as_json
      end,
      meta: { page: page, per_page: per_page, total: total },
    }
  end

  def mark_read
    return head :unprocessable_entity if params[:message_id].blank?

    membership = membership_for_current_user
    return head :ok unless membership

    new_id = params[:message_id].to_i
    return head :ok if membership.last_read_message_id.to_i >= new_id

    membership.update(last_read_message_id: new_id)
    broadcast_read_receipt(new_id)
    head :ok
  end

  private

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:room_id])
  end

  def fetch_message
    @message = @room.messages.find(params[:id])
  end

  def authorize_room_access
    return if @room.member?(Current.user) || Current.account_user.administrator?

    head :forbidden
  end

  def membership_for_current_user
    @membership_for_current_user ||= @room.memberships.find_by(user_id: Current.user.id, left_at: nil)
  end

  def can_delete?(message)
    message.sender_user_id == Current.user.id || Current.account_user.administrator?
  end

  def message_params
    params.require(:message).permit(:content, :sticker_id, content_attributes: {})
  end

  # Converte uploads de imagem pra WebP (PNG/JPG/HEIC viram .webp ~70% menor).
  # GIFs e WebPs já existentes passam batido. Falha de conversão = upload original.
  def webp_converted_attachments
    Array(params.dig(:message, :attachments)).map do |upload|
      InternalChat::ImageWebpConverter.call(upload)
    end
  end

  # Parse de content_attributes que cobre os 2 caminhos de envio:
  # - JSON normal (sem anexos): chega como Hash via strong params
  # - FormData (com anexos): chega como JSON string serializado pelo cliente
  # Sem isso, replies com anexo perdiam o `in_reply_to` (e agora perderiam
  # também o `quoted_message` do "responder no particular").
  #
  # SEC-21 (auditoria 2026-05-18): allowlist de keys após parse — antes
  # `to_unsafe_h` passava qualquer hash do cliente direto pra
  # MessageDispatcher (que persistia em `content_attributes` jsonb).
  # Cliente podia injetar keys arbitrárias (ex: forjar `account_id`,
  # `room_id`, `system_notifier_key`) que outros listeners interpretam.
  ALLOWED_CONTENT_ATTRIBUTES = %w[
    in_reply_to
    quoted_message
    mentioned_user_ids
    mentioned_ai_agent_ids
    mentioned_all
  ].freeze

  def parsed_content_attributes
    raw = params.dig(:message, :content_attributes)
    parsed = parse_raw_attributes(raw)
    parsed.slice(*ALLOWED_CONTENT_ATTRIBUTES)
  end

  def parse_raw_attributes(raw)
    return {} if raw.blank?
    return raw.to_unsafe_h.stringify_keys if raw.respond_to?(:to_unsafe_h)
    return raw.to_h.stringify_keys if raw.is_a?(Hash)
    return JSON.parse(raw) if raw.is_a?(String)

    {}
  rescue JSON::ParserError
    {}
  end

  # Valida que o sticker_id pertence à conta atual ou é um default global.
  def resolved_sticker_id
    sid = message_params[:sticker_id]
    return nil if sid.blank?

    InternalChat::Sticker
      .where(account_id: [Current.account.id, nil])
      .where(id: sid)
      .pick(:id)
  end

  def page_size
    [[params[:limit].to_i, 1].max, 100].min.zero? ? 30 : [params[:limit].to_i, 100].min
  end

  # Broadcast pra todos os membros da sala (incluindo sender) que a mensagem
  # mudou — handlers do frontend reagem com `internal_chat.message.updated`.
  # Cada membro recebe um payload com `is_favorited` calculado para ele mesmo
  # (favorito é estado por usuário).
  #
  # ARCH-21 (audit 2026-05-19): block API porque cada user precisa de
  # MessageSerializer próprio (current_user: user pra computar `is_favorited`).
  def broadcast_message_change(message)
    reloaded = message.reload
    user_ids = @room.memberships.active.where.not(user_id: nil).pluck(:user_id).uniq

    InternalChat::UserBroadcaster.each(user_ids: user_ids) do |user|
      payload = {
        event: 'internal_chat.message.updated',
        data: InternalChat::MessageSerializer.new(reloaded, current_user: user).as_json,
      }
      ActionCable.server.broadcast(user.pubsub_token, payload)
    end
  end

  # Pré-busca em batch pra evitar N+1 no `index`.
  def current_user_favorited_ids(message_ids)
    return [] if message_ids.empty?

    InternalChat::MessageFavorite
      .where(user_id: Current.user.id, message_id: message_ids)
      .pluck(:message_id)
  end

  # PERF-11 (auditoria 2026-05-18): debounce leading-edge. Sem isso, abrir
  # uma sala com 200 mensagens marcava cada uma como lida → 200 broadcasts
  # pra cada outro membro. Agora: 1ª call dispara, próximas dentro da janela
  # de DEBOUNCE_INTERVAL só atualizam DB (last_read_message_id já é canônico).
  # Próxima call APÓS a janela dispara de novo com o id mais recente.
  # UX: outros membros veem read receipt "atrasado em até 2s" — aceitável.
  READ_RECEIPT_DEBOUNCE_INTERVAL = 2.seconds

  def broadcast_read_receipt(message_id)
    return if recently_broadcasted_read_receipt?

    payload = {
      event: 'internal_chat.read_receipt.updated',
      data: {
        account_id: @room.account_id,
        room_id: @room.id,
        user_id: Current.user.id,
        last_read_message_id: message_id,
      },
    }
    broadcast_to_room_members(payload, exclude_self: true)

    Rails.cache.write(read_receipt_debounce_key, true, expires_in: READ_RECEIPT_DEBOUNCE_INTERVAL)
  rescue StandardError => e
    Rails.logger.warn("[InternalChat::Messages] broadcast_read_receipt cache write skipped: #{e.message}")
  end

  def recently_broadcasted_read_receipt?
    Rails.cache.exist?(read_receipt_debounce_key)
  rescue StandardError
    false # Se Redis cair, melhor broadcastar (sem rate limit) do que silenciar
  end

  def read_receipt_debounce_key
    "internal_chat:read_receipt_debounce:#{@room.id}:#{Current.user.id}"
  end

  # ARCH-21 (audit 2026-05-19): wrapper fino sobre UserBroadcaster.call
  # mantendo a semântica `exclude_self` (uso interno do controller).
  def broadcast_to_room_members(payload, exclude_self: false)
    user_ids = @room.memberships.active.where.not(user_id: nil).pluck(:user_id).uniq
    user_ids.delete(Current.user.id) if exclude_self

    InternalChat::UserBroadcaster.call(user_ids: user_ids, payload: payload)
  end
end
