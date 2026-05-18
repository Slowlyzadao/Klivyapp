module InternalChat
  # LGPD Art. 18 — direito ao apagamento. Soft-deleta mensagens (placeholder
  # "Mensagem apagada" pra preservar coerência da thread), remove conteúdos
  # privados (content/content_attributes), encerra memberships e apaga
  # mentions. Não apaga a Room — outros membros podem ainda querer histórico.
  #
  # Idempotente: re-execução é segura (skip-if-already).
  class PurgeUserDataJob < ApplicationJob
    queue_as :low

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user

      # Soft-delete mensagens
      InternalChat::Message.where(sender_user_id: user_id, deleted_at: nil)
                           .find_each do |msg|
        msg.update!(deleted_at: Time.current, content: nil, content_attributes: {})
      end

      # Encerra memberships
      InternalChat::Membership.where(user_id: user_id, left_at: nil)
                              .update_all(left_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      # Apaga mentions (já são derivadas de mensagens; sem valor histórico isolado)
      InternalChat::Mention.where(user_id: user_id).delete_all

      Rails.logger.info("[InternalChat] purged data for user_id=#{user_id}")
    rescue StandardError => e
      Rails.logger.error("[InternalChat::PurgeUserDataJob] user_id=#{user_id} #{e.class}: #{e.message}")
      raise
    end
  end
end
