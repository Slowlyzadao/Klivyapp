module InternalChat
  class MessageFavorite < ApplicationRecord
    self.table_name = 'internal_chat_message_favorites'

    belongs_to :user
    belongs_to :account
    belongs_to :message, class_name: 'InternalChat::Message'

    validates :user_id, uniqueness: { scope: :message_id }
  end
end
