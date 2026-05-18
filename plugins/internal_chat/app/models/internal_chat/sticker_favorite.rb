module InternalChat
  class StickerFavorite < ApplicationRecord
    self.table_name = 'internal_chat_sticker_favorites'

    belongs_to :user
    belongs_to :sticker, class_name: 'InternalChat::Sticker'

    validates :user_id, uniqueness: { scope: :sticker_id }
  end
end
