module InternalChat
  class StickerSerializer
    def initialize(sticker, current_user:, favorite_ids: nil)
      @sticker = sticker
      @current_user = current_user
      @favorite_ids = favorite_ids # Set/Array opcional pra evitar N+1.
    end

    def as_json
      {
        id: @sticker.id,
        account_id: @sticker.account_id,
        name: @sticker.name,
        kind: @sticker.kind,
        category: @sticker.category,
        image_url: @sticker.image_url,
        width: @sticker.width,
        height: @sticker.height,
        file_size: @sticker.file_size,
        created_by_user_id: @sticker.created_by_user_id,
        created_at: @sticker.created_at,
        is_favorite: favorite?,
        is_mine: @sticker.created_by_user_id == @current_user&.id,
        is_default: @sticker.kind == 'default',
      }
    end

    private

    def favorite?
      return @favorite_ids.include?(@sticker.id) if @favorite_ids
      return false unless @current_user

      @sticker.favorited_by?(@current_user)
    end
  end
end
