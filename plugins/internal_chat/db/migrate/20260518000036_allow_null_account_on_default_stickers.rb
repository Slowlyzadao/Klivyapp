class AllowNullAccountOnDefaultStickers < ActiveRecord::Migration[7.1]
  def up
    change_column_null :internal_chat_stickers, :account_id, true
  end

  def down
    change_column_null :internal_chat_stickers, :account_id, false
  end
end
