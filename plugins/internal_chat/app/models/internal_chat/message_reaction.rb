module InternalChat
  class MessageReaction < ApplicationRecord
    self.table_name = 'internal_chat_message_reactions'

    # Emojis padrão expostos pelo picker rápido do menu de ações. Outros
    # emojis ainda podem ser persistidos via API (futuro picker completo);
    # essa lista é só pra renderizar a row no UI sem hardcodar no Vue.
    DEFAULT_EMOJIS = %w[👍 ❤️ 😂 😮 😢 🙏].freeze

    belongs_to :user
    belongs_to :account
    belongs_to :message, class_name: 'InternalChat::Message'

    validates :emoji, presence: true, length: { maximum: 16 }
    validates :user_id, uniqueness: { scope: :message_id }
    validate  :denormalized_fields_match_message

    private

    # MT-13 (auditoria 2026-05-18): `account_id` e `room_id` são
    # denormalizados por performance (queries por inbox/sala sem JOIN).
    # Cliente craftado pode tentar gravar com room_id/account_id de outra
    # sala — corrompe agregados e audit logs. Validação fail-fast.
    def denormalized_fields_match_message
      return if message.nil?

      expected_room_id = message.room_id
      expected_account_id = message.room.account_id

      errors.add(:room_id, 'must match message.room_id') if room_id != expected_room_id
      errors.add(:account_id, 'must match message.room.account_id') if account_id != expected_account_id
    end
  end
end
