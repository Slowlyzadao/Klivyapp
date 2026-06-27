module InternalChat
  # Fan-out helper for ActionCable broadcasts via `user.pubsub_token`.
  # Centraliza o pattern repetido em controllers/jobs/services do plugin
  # (ARCH-21 — audit 2026-05-19): 1 SQL `User.where(id: ids).find_each`
  # + iteração + broadcast. Erros opcionalmente isolados por destinatário.
  #
  # Dois APIs:
  #
  #   # 1) Payload único pra N users
  #   InternalChat::UserBroadcaster.call(
  #     user_ids: [1, 2, 3],
  #     payload: { event: 'internal_chat.room.updated', data: ... }
  #   )
  #
  #   # 2) Block — quando payload varia por user (serializer com
  #   #    current_user: user) ou múltiplos broadcasts por user (mention)
  #   InternalChat::UserBroadcaster.each(user_ids: ids) do |user|
  #     ActionCable.server.broadcast(user.pubsub_token, ...)
  #   end
  #
  # `isolate: true` envolve cada entrega em `rescue StandardError`
  # (logado como warn) — RT-3 padrão pra room destroy + room.updated.
  # Por padrão erros propagam (Sidekiq retry para jobs, 500 pra controllers).
  class UserBroadcaster
    def self.call(user_ids:, payload:, isolate: false, log_tag: nil)
      each(user_ids: user_ids, isolate: isolate, log_tag: log_tag) do |user|
        ActionCable.server.broadcast(user.pubsub_token, payload)
      end
    end

    def self.each(user_ids:, isolate: false, log_tag: nil)
      ids = Array(user_ids).compact.uniq
      return 0 if ids.empty?

      delivered = 0
      tag = log_tag || name

      User.where(id: ids).find_each do |user|
        if isolate
          begin
            yield(user)
            delivered += 1
          rescue StandardError => e
            Rails.logger.warn("[#{tag}] broadcast failed user=#{user.id}: #{e.class}: #{e.message}")
          end
        else
          yield(user)
          delivered += 1
        end
      end

      delivered
    end
  end
end
