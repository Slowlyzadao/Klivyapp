module InternalChat
  # LGPD Art. 18 — direito ao apagamento. Soft-deleta mensagens (placeholder
  # "Mensagem apagada" pra preservar coerência da thread), remove conteúdos
  # privados (content/content_attributes), encerra memberships e apaga
  # mentions. Não apaga a Room — outros membros podem ainda querer histórico.
  #
  # Idempotente: re-execução é segura (skip-if-already).
  #
  # Multi-tenant (MT-6, auditoria 2026-05-18): SEMPRE recebe account_id e
  # scopa todas as queries. Sem isso, um user que é membro de várias contas
  # teria dados apagados em TODAS quando uma só requisitou — spillover LGPD
  # de cross-account.
  class PurgeUserDataJob < ApplicationJob
    queue_as :low

    def perform(user_id, account_id:)
      user = User.find_by(id: user_id)
      return unless user

      account = Account.find_by(id: account_id)
      return unless account

      purge_messages(user_id, account.id)
      purge_memberships(user_id, account.id)
      purge_mentions(user_id, account.id)

      Rails.logger.info("[InternalChat] purged data for user_id=#{user_id} account_id=#{account.id}")
    rescue StandardError => e
      Rails.logger.error("[InternalChat::PurgeUserDataJob] user_id=#{user_id} account_id=#{account_id} #{e.class}: #{e.message}")
      raise
    end

    private

    # Soft-delete: marca deleted_at + zera content/content_attributes pra
    # preservar coerência da thread (mostra "Mensagem apagada" no UI) mas
    # remove o conteúdo sensível. Scoped por internal_chat_rooms.account_id.
    def purge_messages(user_id, account_id)
      InternalChat::Message
        .joins(:room)
        .where(internal_chat_rooms: { account_id: account_id })
        .where(sender_user_id: user_id, deleted_at: nil)
        .find_each do |msg|
        msg.update!(deleted_at: Time.current, content: nil, content_attributes: {})
      end
    end

    # Encerra memberships ativas (left_at = now) só nas salas desta conta.
    def purge_memberships(user_id, account_id)
      InternalChat::Membership
        .joins(:room)
        .where(internal_chat_rooms: { account_id: account_id })
        .where(user_id: user_id, left_at: nil)
        .update_all(left_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    # Apaga mentions — `Mention` tem account_id denormalizado, filtro direto.
    def purge_mentions(user_id, account_id)
      InternalChat::Mention.where(user_id: user_id, account_id: account_id).delete_all
    end
  end
end
