module InternalChat
  # Exporta tudo o que um usuário gerou no chat interno (LGPD Art. 18 — direito
  # de portabilidade). Retorna hash serializável; quem chama escreve em
  # JSON/zip conforme a política.
  #
  # Multi-tenant (MT-7, auditoria 2026-05-18): SEMPRE recebe account. Sem isso,
  # um user que é membro de várias clínicas teria dados de TODAS exportados
  # quando uma só requisitou — vazamento cross-account em payload LGPD.
  #
  # SEC-16 (auditoria 2026-05-18): autorização defensiva no nível do service.
  # `caller:` é o User invocando o export. Aceita:
  #   - caller == user (próprio user exportando seus dados — Art. 18 self-service),
  #   - caller é administrator da conta (export iniciado por admin via console
  #     ou futuro endpoint LGPD).
  # Qualquer outro caller raise NotAuthorizedError. Sem este gate, futuro
  # endpoint que esquecer de validar acaba expondo dados de qualquer user.
  class DataExporter
    class NotAuthorizedError < StandardError; end

    def self.call(user:, account:, caller: nil)
      new(user, account, caller).call
    end

    def initialize(user, account, caller_user = nil)
      @user = user
      @account = account
      @caller = caller_user
    end

    def call
      authorize!
      {
        user_id: @user.id,
        account_id: @account.id,
        exported_at: Time.current.iso8601,
        rooms: rooms_payload,
        messages: messages_payload,
        mentions_received: mentions_payload,
      }
    end

    private

    # SEC-16: caller precisa ser o próprio user OU admin da conta. Sem
    # caller (caso console/script sem contexto), log.warn + permite —
    # backwards-compatible mas observável (a longo prazo todo caller
    # passa caller: explicitamente).
    def authorize!
      if @caller.nil?
        Rails.logger.warn(
          '[InternalChat::DataExporter] called without caller — assume console/job context. ' \
          "user_id=#{@user.id} account_id=#{@account.id}"
        )
        return
      end

      return if @caller.id == @user.id
      return if administrator?(@caller, @account)

      raise NotAuthorizedError,
            "caller=#{@caller.id} cannot export data for user=#{@user.id} on account=#{@account.id}"
    end

    def administrator?(user, account)
      au = account.account_users.find_by(user_id: user.id)
      au&.administrator? || false
    end

    def rooms_payload
      # Membership scoped via JOIN com internal_chat_rooms.account_id — não
      # podemos confiar em `account_id` direto na membership pq o modelo só
      # tem `room_id` e `user_id`.
      InternalChat::Membership
        .joins(:room)
        .where(internal_chat_rooms: { account_id: @account.id })
        .where(user_id: @user.id)
        .includes(:room)
        .map do |m|
        {
          room_id: m.room_id,
          role: m.role,
          joined_at: m.joined_at,
          left_at: m.left_at,
          room_kind: m.room.kind,
          room_name: m.room.name,
        }
      end
    end

    def messages_payload
      InternalChat::Message
        .joins(:room)
        .where(internal_chat_rooms: { account_id: @account.id })
        .where(sender_user_id: @user.id)
        .order(:created_at)
        .map do |msg|
        {
          message_id: msg.id,
          room_id: msg.room_id,
          content: msg.content,
          content_type: msg.content_type,
          content_attributes: msg.content_attributes,
          deleted_at: msg.deleted_at,
          created_at: msg.created_at,
          attachment_count: msg.attachments.count,
        }
      end
    end

    def mentions_payload
      # Mention tem account_id denormalizado, filtro direto.
      InternalChat::Mention
        .where(user_id: @user.id, account_id: @account.id)
        .order(:created_at)
        .map do |m|
        {
          mention_id: m.id,
          message_id: m.message_id,
          read_at: m.read_at,
          created_at: m.created_at,
        }
      end
    end
  end
end
