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
      raise ArgumentError, 'kind inválido' unless InternalChat::Room::KINDS.include?(@kind)
      raise ArgumentError, 'pelo menos 1 outro membro' if other_ids.empty?

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
      raise ArgumentError, "usuários fora da conta: #{missing.join(', ')}" if missing.any?
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
      raise ArgumentError, 'grupo precisa de nome' if @name.blank?

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
    def broadcast_to_other_members(room)
      other_ids.each do |uid|
        user = User.find_by(id: uid)
        next unless user

        payload = {
          event: 'internal_chat.room.updated',
          data: InternalChat::RoomSerializer.new(room, current_user: user).as_json,
        }
        ActionCable.server.broadcast(user.pubsub_token, payload)
      end
    rescue StandardError => e
      Rails.logger.warn "[InternalChat::RoomCreator] broadcast failed: #{e.class}: #{e.message}"
    end
  end
end
