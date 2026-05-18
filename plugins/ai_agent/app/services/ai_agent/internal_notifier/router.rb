module AiAgent
  module InternalNotifier
    # Resolve, dado uma `account` + `event_key`, qual `InternalChat::Room` a
    # Bea deve postar, conforme o template configurado pela clínica.
    #
    # Suporta 3 tipos de destino:
    #   - 'room'     → posta na sala configurada (validada ainda existir)
    #   - 'user'     → posta numa DM 1:1 entre Bea e o user (idempotente)
    #   - 'disabled' → retorna nil (clínica desligou esse evento)
    #
    # Sem destino válido = não dispara. Decisão Apêndice F: clínica que não
    # configurou template não recebe notificação — sem auto-magia silenciosa.
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
    class Router
      Result = Struct.new(:room, :template, keyword_init: true)

      def self.resolve(account:, event_key:)
        new(account, event_key).resolve
      end

      def initialize(account, event_key)
        @account = account
        @event_key = event_key
      end

      def resolve
        template = AiAgent::InternalNotificationTemplate.find_by(
          account_id: @account.id,
          event_key: @event_key
        )

        return Result.new(room: nil, template: nil) if template.nil? || template.disabled?

        room = resolve_room_for(template)
        if room.nil?
          Rails.logger.warn(
            "[InternalNotifier::Router] template ##{template.id} (event=#{@event_key}) " \
            "aponta pra #{template.target_type}:#{template.target_id} que não existe. Notificação não enviada."
          )
        end

        Result.new(room: room, template: template)
      end

      private

      def resolve_room_for(template)
        case template.target_type
        when 'room' then resolve_room(template.target_id)
        when 'user' then resolve_dm(template.target_id)
        end
      end

      def resolve_room(room_id)
        ::InternalChat::Room.find_by(id: room_id, account_id: @account.id)
      end

      def resolve_dm(user_id)
        bea = ::InternalChat::BeaResolver.for_account(@account)
        return nil unless bea

        user = ::AccountUser.where(account_id: @account.id, user_id: user_id).exists? ? ::User.find_by(id: user_id) : nil
        return nil unless user

        find_or_create_bea_dm(bea, user)
      end

      def find_or_create_bea_dm(bea, user)
        # DM idempotente entre Bea (ai_agent_id) e User. Procura sala kind='direct'
        # com exatamente esses 2 membros.
        existing = ::InternalChat::Room
                   .joins(:memberships)
                   .where(account_id: @account.id, kind: 'direct')
                   .where(internal_chat_memberships: { ai_agent_id: bea.id })
                   .where(id: ::InternalChat::Membership.where(user_id: user.id).select(:room_id))
                   .first
        return existing if existing

        ::InternalChat::Room.transaction do
          room = ::InternalChat::Room.create!(
            account_id: @account.id,
            kind: 'direct',
            name: nil,
            created_by_user_id: nil
          )
          room.memberships.create!(ai_agent_id: bea.id, role: 'member', joined_at: Time.current)
          room.memberships.create!(user_id: user.id, role: 'member', joined_at: Time.current)
          room
        end
      end
    end
  end
end
