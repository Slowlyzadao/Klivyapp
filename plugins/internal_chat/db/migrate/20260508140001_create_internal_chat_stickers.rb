class CreateInternalChatStickers < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_stickers do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.bigint  :created_by_user_id # NULL para stickers default da plataforma
      t.string  :name, limit: 120
      t.string  :kind, null: false, default: 'account' # 'account' | 'default'
      t.integer :width
      t.integer :height
      t.integer :file_size
      t.timestamps
    end

    add_index :internal_chat_stickers, [:account_id, :kind]
    add_index :internal_chat_stickers, :created_by_user_id

    create_table :internal_chat_sticker_favorites do |t|
      t.references :user,    null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :sticker, null: false, foreign_key: { to_table: :internal_chat_stickers, on_delete: :cascade }
      t.timestamps
    end

    add_index :internal_chat_sticker_favorites, [:user_id, :sticker_id], unique: true,
              name: 'idx_sticker_fav_uniq'

    add_reference :internal_chat_messages, :sticker,
                  foreign_key: { to_table: :internal_chat_stickers, on_delete: :nullify },
                  null: true, index: true
  end
end
