module InternalChat
  class RoomSerializer
    # Sentinel pra distinguir "não passou hint preloaded" de "passou nil/vazio
    # explicitamente". `nil` é valor válido pra last_message (sala recém
    # criada sem mensagens) — então não dá pra usar nil como "buscar do DB".
    NOT_PROVIDED = Object.new.freeze
    private_constant :NOT_PROVIDED

    # PERF-1 (auditoria 2026-05-18): aceita `memberships` e `last_message`
    # pré-carregados pelo caller (RoomsController#index) pra evitar N+1.
    # Quando não fornecidos (`#show`, broadcasts pontuais), faz query
    # individual — mantém compat com todos os call sites.
    def initialize(room, current_user:, memberships: NOT_PROVIDED, last_message: NOT_PROVIDED)
      @room = room
      @current_user = current_user
      @preloaded_memberships = memberships
      @preloaded_last_message = last_message
    end

    def as_json
      memberships = resolve_memberships
      my_membership = memberships.find { |m| m.user_id == @current_user.id }
      last = resolve_last_message

      {
        id: @room.id,
        # account_id é obrigatório no payload de cable events (filtro do
        # ActionCableConnector core).
        account_id: @room.account_id,
        kind: @room.kind,
        name: @room.display_name_for(@current_user),
        description: @room.description,
        avatar_url: avatar_url_for(memberships),
        # Muda só quando a foto do grupo realmente troca (created_at do
        # attachment) — o frontend usa como `:key` do Avatar pra forçar o
        # refresh do <img> sem F5. NÃO usar avatar_url pra isso: ela muda a
        # cada serialização (token tem expires_at), o que causaria remount/
        # flicker em toda atualização da sala.
        avatar_updated_at: group_avatar_timestamp,
        # Arquivar/silenciar são POR-USUÁRIO: refletem a membership do
        # current_user, não estado global do room.
        archived_at: my_membership&.archived_at,
        muted_until: my_membership&.muted_until,
        last_message_at: @room.last_message_at,
        last_message: last ? InternalChat::MessageSerializer.new(last).as_json : nil,
        unread_count: my_membership ? my_membership.unread_count : 0,
        members: memberships.map { |m| membership_payload(m) },
        created_by_user_id: @room.created_by_user_id,
        created_at: @room.created_at,
      }
    end

    private

    def resolve_memberships
      return @preloaded_memberships if @preloaded_memberships != NOT_PROVIDED

      @room.memberships.active.includes(:user).to_a
    end

    def resolve_last_message
      return @preloaded_last_message if @preloaded_last_message != NOT_PROVIDED

      @room.messages.visible.order(id: :desc).first
    end

    def avatar_url_for(memberships)
      return @room.avatar_url if @room.group?

      other = memberships.map(&:user).compact.find { |u| u.id != @current_user.id }
      other&.respond_to?(:avatar_url) ? other.avatar_url : nil
    end

    # created_at do attachment do avatar do grupo — muda só quando a foto
    # troca. nil quando não é grupo ou não há foto (DM usa o avatar do user).
    def group_avatar_timestamp
      return nil unless @room.group?

      @room.avatar.attachment&.created_at
    end

    def membership_payload(m)
      is_ai = m.ai_agent_id.present?
      {
        id: m.id,
        user_id: m.user_id,
        ai_agent_id: m.ai_agent_id,
        role: m.role,
        name: is_ai ? InternalChat::BeaResolver::DISPLAY_LABEL : m.user&.available_name,
        avatar_url: m.user&.respond_to?(:avatar_url) ? m.user&.avatar_url : nil,
        is_ai: is_ai,
        last_read_message_id: m.last_read_message_id,
      }
    end
  end
end
