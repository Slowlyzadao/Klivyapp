module InternalChat
  class StickerFavorite < ApplicationRecord
    self.table_name = 'internal_chat_sticker_favorites'

    belongs_to :user
    belongs_to :account
    belongs_to :sticker, class_name: 'InternalChat::Sticker'

    # MT-11: unique inclui account_id — mesmo user pode favoritar mesmo
    # default sticker em N contas distintas (cada favorite vira 1 row).
    validates :user_id, uniqueness: { scope: %i[account_id sticker_id] }

    # MT-11: defesa contra StickerFavorite "cross-tenant" — favorite de
    # sticker custom da conta A salvo com account_id=B é inválido.
    # Defaults (sticker.account_id IS NULL) podem ser favoritados em
    # qualquer conta — caso legítimo.
    validate :account_matches_sticker_when_custom

    private

    def account_matches_sticker_when_custom
      return if sticker.nil?
      return if sticker.account_id.nil? # default — qualquer conta pode favoritar
      return if sticker.account_id == account_id

      errors.add(:account_id, 'deve coincidir com a conta do sticker custom')
    end
  end
end
