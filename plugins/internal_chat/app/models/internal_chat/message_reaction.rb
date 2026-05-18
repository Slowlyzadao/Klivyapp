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
  end
end
