class Api::V1::Accounts::InternalChat::TypingController < Api::V1::Accounts::BaseController
  before_action :fetch_room
  before_action -> { authorize(@room, policy_class: InternalChat::TypingPolicy) }

  # PERF-12 (auditoria 2026-05-18): rate limit server-side. Frontend já tem
  # debounce de 3s, mas se um keystroke disparar 2 calls back-to-back (race
  # de digit + click) cada uma faria fan-out pra todos os outros membros.
  # Em sala com 50 membros: 50 × 49 = 2450 broadcasts/segundo no pior caso.
  # Limite de 1 broadcast/usuário/sala/segundo cobre o caso real (frontend
  # debounce ~3s) sem cortar nada visivelmente.
  #
  # Limite só aplicado pra `active=true` (start). `active=false` (stop)
  # SEMPRE passa — queremos comunicar parada imediatamente pra UX
  # de outros membros não verem "Fulano digitando" infinito.
  TYPING_RATE_INTERVAL = 1.second

  # POST /rooms/:room_id/typing
  # body: { active: true | false }
  # Broadcast efêmero — não persiste nada. Frontend usa debounce de ~3s.
  def create
    active = ActiveModel::Type::Boolean.new.cast(params[:active])

    return head :no_content if active && typing_rate_limited?

    payload = {
      event: 'internal_chat.typing',
      data: {
        account_id: @room.account_id,
        room_id: @room.id,
        user_id: Current.user.id,
        user_name: Current.user.available_name,
        active: active,
      },
    }
    broadcast_typing(payload)

    Rails.cache.write(typing_rate_key, true, expires_in: TYPING_RATE_INTERVAL) if active
    head :no_content
  rescue StandardError => e
    Rails.logger.warn("[InternalChat::Typing] cache write skipped: #{e.message}")
    head :no_content
  end

  private

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:room_id])
  end

  def typing_rate_limited?
    Rails.cache.exist?(typing_rate_key)
  rescue StandardError
    false # Redis down → melhor broadcastar do que silenciar
  end

  def typing_rate_key
    "internal_chat:typing_rate:#{@room.id}:#{Current.user.id}"
  end

  # ARCH-21 (audit 2026-05-19): fan-out via UserBroadcaster.call —
  # mesmo payload pra todos os outros membros (self já removido).
  def broadcast_typing(payload)
    user_ids = @room.memberships.active.where.not(user_id: nil).pluck(:user_id)
    user_ids.delete(Current.user.id)

    InternalChat::UserBroadcaster.call(user_ids: user_ids, payload: payload)
  end
end
