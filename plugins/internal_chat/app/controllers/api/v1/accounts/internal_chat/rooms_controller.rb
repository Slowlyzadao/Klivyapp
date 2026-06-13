class Api::V1::Accounts::InternalChat::RoomsController < Api::V1::Accounts::BaseController
  before_action :fetch_room, only: [:show, :update, :destroy, :archive, :unarchive, :mute, :unmute, :update_avatar, :remove_avatar]
  before_action :authorize_action

  def authorize_action
    # Pundit precisa do registro real (não da classe) para checar membership.
    target = @room || InternalChat::Room
    authorize(target, "#{action_name}?".to_sym)
  end

  # PERF-15 (auditoria 2026-05-18): cap default + paginação opt-in. Sem
  # `?page=`, retorna primeira página (200). Contas com >200 salas paginam
  # explicitamente. `meta` na resposta deixa frontend saber total e current
  # page sem regredir clientes existentes (só adiciona campos).
  ROOMS_PER_PAGE_DEFAULT = 200
  ROOMS_PER_PAGE_MAX = 200

  def index
    page = (params[:page].presence || 1).to_i.clamp(1, 10_000)
    per_page = (params[:per_page].presence || ROOMS_PER_PAGE_DEFAULT)
               .to_i.clamp(1, ROOMS_PER_PAGE_MAX)
    offset = (page - 1) * per_page

    # Postgres rejeita DISTINCT + ORDER BY com expressões fora do SELECT, então
    # buscamos os ids via subquery e ordenamos sem JOIN (mais barato também).
    # Arquivar é por-membership: lista padrão = não-arquivadas do usuário;
    # `?archived=true` = só as arquivadas (aba "Arquivadas").
    memberships = InternalChat::Membership.where(user_id: Current.user.id, left_at: nil)
    memberships = if ActiveModel::Type::Boolean.new.cast(params[:archived])
                    memberships.archived
                  else
                    memberships.not_archived
                  end
    room_ids = memberships.pluck(:room_id)
    base = Current.account.internal_chat_rooms.where(id: room_ids)
    total = base.count
    rooms = base.recent
                .offset(offset)
                .limit(per_page)
                .to_a
    visible_room_ids = rooms.map(&:id)

    # PERF-1 (auditoria 2026-05-18): pré-carrega memberships+users e a última
    # mensagem visível por sala — antes cada call ao RoomSerializer fazia 2
    # queries extras (1 pra memberships incluído users, 1 pra last message).
    # 100 salas iam 200+ queries; agora 3 totais.
    memberships_by_room = preloaded_memberships(visible_room_ids)
    last_messages_by_room = preloaded_last_messages(visible_room_ids)

    payloads = rooms.map do |r|
      InternalChat::RoomSerializer.new(
        r,
        current_user: Current.user,
        memberships: memberships_by_room[r.id] || [],
        last_message: last_messages_by_room[r.id]
      ).as_json
    end
    render json: {
      data: payloads,
      meta: { page: page, per_page: per_page, total: total }
    }
  end

  def show
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  def create
    result = InternalChat::RoomCreator.call(
      account: Current.account,
      current_user: Current.user,
      kind: room_params[:kind] || 'direct',
      member_user_ids: room_params[:member_user_ids],
      name: room_params[:name],
      description: room_params[:description],
      add_bea: ActiveModel::Type::Boolean.new.cast(room_params[:add_bea]),
    )
    render json: { data: InternalChat::RoomSerializer.new(result.room, current_user: Current.user).as_json },
           status: result.created ? :created : :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    name_was = @room.name
    description_was = @room.description
    @room.update!(room_params.slice(:name, :description, :archived_at))

    if @room.group?
      if @room.name != name_was && @room.name.present?
        InternalChat::SystemMessageBuilder.call(
          room: @room, event: :renamed, actor: Current.user, payload: { name: @room.name }
        )
      end
      if @room.description != description_was
        InternalChat::SystemMessageBuilder.call(
          room: @room, event: :description_changed, actor: Current.user
        )
      end
    end
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  def destroy
    # Broadcast ANTES de destruir, pra que cada cliente conectado consiga
    # remover a sala da listagem em tempo real.
    member_user_ids = @room.memberships.where.not(user_id: nil).pluck(:user_id).uniq
    payload = { event: 'internal_chat.room.deleted',
                data: { account_id: @room.account_id, room_id: @room.id } }

    # SEC-7 (auditoria 2026-05-18): admin bypass deixa rastro. Sem este
    # log, deleção de sala por admin (não-criador) não fica auditável.
    # Telemetria + WARN level pra que dashboards e SIEM capturem.
    admin_bypass = Current.account_user.administrator? && @room.created_by_user_id != Current.user.id
    if admin_bypass
      Rails.logger.warn(
        '[InternalChat::RoomsController] admin_destroy_bypass: ' \
        "account=#{Current.account.id} room=#{@room.id} admin_user=#{Current.user.id} " \
        "creator=#{@room.created_by_user_id} room_kind=#{@room.kind}"
      )
    end

    @room.destroy!
    # ARCH-21 (audit 2026-05-19): fan-out via UserBroadcaster.call —
    # `isolate: true` preserva o RT-3 (cada broadcast em rescue isolado:
    # falha pra 1 user — ActionCable transient down, Redis blip — não
    # derruba os outros; sem isso o primeiro raise faria clientes
    # restantes ficar com sala fantasma na UI até reload).
    InternalChat::UserBroadcaster.call(
      user_ids: member_user_ids,
      payload: payload,
      isolate: true,
      log_tag: "InternalChat::RoomsController#destroy room=#{params[:id]}"
    )
    InternalChat::Telemetry.track('room_deleted',
                                  account_id: Current.account.id,
                                  room_id: params[:id],
                                  user_id: Current.user.id,
                                  admin_bypass: admin_bypass,
                                  creator_user_id: @room.created_by_user_id)
    head :ok
  end

  # PATCH /rooms/:id/avatar
  # multipart com `avatar` (file). Atualiza imagem do grupo.
  def update_avatar
    return head :unprocessable_entity if params[:avatar].blank?

    @room.avatar.attach(params[:avatar])
    return render json: { errors: @room.errors.full_messages }, status: :unprocessable_entity unless @room.save

    broadcast_room_update
    render json: { data: InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json }
  end

  # DELETE /rooms/:id/avatar
  def remove_avatar
    @room.avatar.purge if @room.avatar.attached?
    @room.update!(avatar_url: nil)
    broadcast_room_update
    render json: { data: InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json }
  end

  # PATCH /rooms/:id/archive — arquiva a visão do PRÓPRIO usuário (per-membership).
  def archive
    membership = membership_for_current_user
    return head :unprocessable_entity unless membership

    membership.update!(archived_at: Time.current)
    InternalChat::Telemetry.track('room_archived',
                                  account_id: @room.account_id, room_id: @room.id,
                                  user_id: Current.user.id)
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  # PATCH /rooms/:id/unarchive
  def unarchive
    membership = membership_for_current_user
    return head :unprocessable_entity unless membership

    membership.update!(archived_at: nil)
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  # PATCH /rooms/:id/mute
  # body: { mute_until: <iso8601> | null }   nil = mutar indefinido
  def mute
    membership = membership_for_current_user
    return head :unprocessable_entity unless membership

    until_time = params[:mute_until].present? ? Time.zone.parse(params[:mute_until]) : 100.years.from_now
    membership.update!(muted_until: until_time)
    InternalChat::Telemetry.track('room_muted',
                                  account_id: @room.account_id, room_id: @room.id,
                                  user_id: Current.user.id)
    render json: { data: { room_id: @room.id, muted_until: membership.muted_until } }
  end

  # DELETE /rooms/:id/mute
  def unmute
    membership = membership_for_current_user
    return head :unprocessable_entity unless membership

    membership.update!(muted_until: nil)
    render json: { data: { room_id: @room.id, muted_until: nil } }
  end

  def unread_summary
    # PERF-2 (auditoria 2026-05-18): antes essa endpoint executava 1 + N
    # queries (pluck memberships, depois `unread_count` por row faz `.count`
    # por sala). Com 100 salas era 101 queries por carregamento do sidebar.
    # Agora 1 SQL com LEFT JOIN + GROUP BY.
    #
    # NOTA sobre comportamento: a condição
    # `msg.sender_user_id != m.user_id` é tradução fiel do `where.not`
    # original do `Membership#unread_count`. Resultado: mensagens da Bea
    # (sender_user_id NULL, sender_ai_agent_id setado) NÃO contam como
    # unread — preserva comportamento histórico (intencional: chat staff,
    # Bea responde sem virar "msg não lida" pro próprio mencionador).
    # BE-19 (msgs soft-deleted) já endereçado: `msg.deleted_at IS NULL`.
    current_user_id = Current.user.id
    account_room_ids = Current.account.internal_chat_rooms.select(:id)

    rows = InternalChat::Membership
           .joins(<<~SQL.squish)
             LEFT JOIN internal_chat_messages msg
               ON msg.room_id = internal_chat_memberships.room_id
              AND msg.id > COALESCE(internal_chat_memberships.last_read_message_id, 0)
              AND msg.deleted_at IS NULL
              AND msg.sender_user_id != internal_chat_memberships.user_id
           SQL
           .where(user_id: current_user_id, left_at: nil)
           .where(internal_chat_memberships: { room_id: account_room_ids, archived_at: nil })
           .group('internal_chat_memberships.room_id')
           .count('msg.id')
    # rows = { 5 => 12, 7 => 0, 9 => 3, ... } (salas arquivadas já excluídas)

    # Salas silenciadas (mute vigente) continuam mostrando o contador por sala
    # (cinza na lista), mas NÃO somam no total — esse total alimenta o badge de
    # "tem mensagem nova" da sidebar, que é exatamente o que "Silenciar" deve
    # suprimir. Sem isso, o mute era puramente cosmético.
    muted_room_ids = InternalChat::Membership
                     .where(user_id: current_user_id, left_at: nil, archived_at: nil)
                     .where('muted_until IS NOT NULL AND muted_until > ?', Time.current)
                     .pluck(:room_id)
                     .to_set
    total = rows.sum { |room_id, count| muted_room_ids.include?(room_id) ? 0 : count }
    render json: { data: rows, total: total }
  end

  private

  # PERF-1: 1 query SQL com JOIN — carrega todas as memberships ativas das
  # salas visíveis + os users (com avatar_attachment pra evitar N+1 do
  # ActiveStorage). Retorna { room_id => [memberships] }.
  def preloaded_memberships(room_ids)
    return {} if room_ids.empty?

    InternalChat::Membership
      .active
      .where(room_id: room_ids)
      .includes(:user)
      .group_by(&:room_id)
  end

  # PERF-1: 1 query SQL DISTINCT ON (Postgres) — pega a última mensagem
  # visível por sala numa única passada. Alternativa portátil seria
  # subquery `MAX(id) GROUP BY room_id`, bem mais lenta com index scan
  # repetido. Klivy é Postgres-only, então DISTINCT ON é OK.
  def preloaded_last_messages(room_ids)
    return {} if room_ids.empty?

    InternalChat::Message
      .visible
      .where(room_id: room_ids)
      .select('DISTINCT ON (room_id) internal_chat_messages.*')
      .order('room_id, id DESC')
      .index_by(&:room_id)
  end

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:id])
  end

  def membership_for_current_user
    @room.memberships.find_by(user_id: Current.user.id, left_at: nil)
  end

  def room_params
    params.require(:room).permit(:kind, :name, :description, :archived_at, :add_bea, member_user_ids: [])
  end

  def broadcast_room_update
    payload = InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json
    user_ids = @room.memberships.where.not(user_id: nil).pluck(:user_id).uniq

    # ARCH-21 (audit 2026-05-19): fan-out via UserBroadcaster.call —
    # `isolate: true` preserva o RT-3 (cada broadcast isolado).
    InternalChat::UserBroadcaster.call(
      user_ids: user_ids,
      payload: { event: 'internal_chat.room.updated', data: payload },
      isolate: true,
      log_tag: "InternalChat::RoomsController#broadcast_room_update room=#{@room.id}"
    )
  end
end
