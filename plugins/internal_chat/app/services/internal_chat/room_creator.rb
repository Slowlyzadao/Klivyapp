module InternalChat
  # Cria/encontra Room para 1:1 ou grupo. Idempotente em direct: se já existir
  # uma sala 1:1 entre os mesmos dois usuários, retorna a existente em vez de
  # duplicar. Para grupos, sempre cria nova sala.
  class RoomCreator
    Result = Struct.new(:room, :created, keyword_init: true)

    def self.call(account:, current_user:, kind:, member_user_ids:, name: nil, description: nil, add_bea: false)
      new(account, current_user, kind, member_user_ids, name, description, add_bea).call
    end

    def initialize(account, current_user, kind, member_user_ids, name, description, add_bea = false)
      @account = account
      @current_user = current_user
      @kind = kind.to_s
      @member_user_ids = Array(member_user_ids).map(&:to_i).reject(&:zero?).uniq
      @name = name
      @description = description
      @add_bea = add_bea
    end

    def call
      # FE-16/17 (auditoria 2026-05-18): strings migradas pra I18n.
      raise ArgumentError, I18n.t('internal_chat.services.room_creator.kind_invalid') unless InternalChat::Room::KINDS.include?(@kind)
      raise ArgumentError, I18n.t('internal_chat.services.room_creator.members_required') if other_ids.empty?

      validate_account_membership!

      if @kind == 'direct'
        existing = find_existing_direct
        return Result.new(room: existing, created: false) if existing

        create_direct
      else
        create_group
      end
    end

    private

    def other_ids
      @other_ids ||= @member_user_ids - [@current_user.id]
    end

    def all_user_ids
      ([@current_user.id] + other_ids).uniq
    end

    def validate_account_membership!
      account_user_ids = @account.users.where(id: all_user_ids).pluck(:id)
      missing = all_user_ids - account_user_ids
      raise ArgumentError, I18n.t('internal_chat.services.room_creator.users_not_in_account', ids: missing.join(', ')) if missing.any?
    end

    def find_existing_direct
      return nil unless other_ids.size == 1

      other_id = other_ids.first
      @account.internal_chat_rooms
              .where(kind: 'direct')
              .joins(:memberships)
              .where(internal_chat_memberships: { user_id: [@current_user.id, other_id] })
              .group('internal_chat_rooms.id')
              .having('COUNT(DISTINCT internal_chat_memberships.user_id) = 2')
              .first
    end

    def create_direct
      result = ActiveRecord::Base.transaction do
        room = @account.internal_chat_rooms.create!(
          kind: 'direct',
          created_by_user_id: @current_user.id,
        )
        all_user_ids.each do |uid|
          room.memberships.create!(user_id: uid, role: 'member')
        end
        InternalChat::Telemetry.track('room_created',
                                      account_id: @account.id, room_id: room.id, kind: 'direct')
        Result.new(room: room.reload, created: true)
      end
      broadcast_to_other_members(result.room)
      result
    end

    def create_group
      raise ArgumentError, I18n.t('internal_chat.services.room_creator.group_name_required') if @name.blank?

      result = ActiveRecord::Base.transaction do
        room = @account.internal_chat_rooms.create!(
          kind: 'group',
          name: @name,
          description: @description,
          created_by_user_id: @current_user.id,
        )
        room.memberships.create!(user_id: @current_user.id, role: 'owner')
        other_ids.each { |uid| room.memberships.create!(user_id: uid, role: 'member') }
        add_bea_membership!(room) if @add_bea
        InternalChat::Telemetry.track('room_created',
                                      account_id: @account.id, room_id: room.id,
                                      kind: 'group', members: all_user_ids.size, with_bea: @add_bea)
        Result.new(room: room.reload, created: true)
      end
      broadcast_to_other_members(result.room)
      result
    end

    def add_bea_membership!(room)
      bea = InternalChat::BeaResolver.for_account(@account)
      return unless bea

      room.memberships.create!(ai_agent_id: bea.id, role: 'member', joined_at: Time.current)
    end

    # Sem isso, quando A cria uma DM com B, o frontend de B não sabe que a
    # sala existe — a mensagem subsequente chega via cable mas não entra em
    # `records`, então a lista de conversas de B não atualiza. Broadcast por
    # usuário (cada um vê o RoomSerializer com seu próprio current_user).
    #
    # ARCH-21 (audit 2026-05-19): fan-out via UserBroadcaster.each — block
    # API necessária porque cada user precisa de RoomSerializer próprio
    # (current_user diff). `isolate: true` substitui o `rescue` envolvendo
    # tudo: agora 1 user com pubsub_token quebrado não derruba os demais
    # (mesma garantia do RT-3 em RoomsController#destroy/update).
    def broadcast_to_other_members(room)
      return if other_ids.empty?

      InternalChat::UserBroadcaster.each(
        user_ids: other_ids,
        isolate: true,
        log_tag: 'InternalChat::RoomCreator'
      ) do |user|
        payload = {
          event: 'internal_chat.room.updated',
          data: InternalChat::RoomSerializer.new(room, current_user: user).as_json,
        }
        ActionCable.server.broadcast(user.pubsub_token, payload)
      end
    end
  end
end
