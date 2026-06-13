class CreateInternalChatMessageFavorites < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_message_favorites do |t|
      t.references :user,    null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :message, null: false, foreign_key: { to_table: :internal_chat_messages, on_delete: :cascade }
      # Denormalizados pra filtrar listagens sem joinar a árvore toda. account_id
      # tem FK; room_id tem index pra "favoritos desta sala".
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.bigint     :room_id, null: false
      t.timestamps
    end

    # Um usuário só pode favoritar uma mensagem uma vez.
    add_index :internal_chat_message_favorites, [:user_id, :message_id], unique: true,
              name: 'idx_msg_fav_uniq'
    # Listagem "meus favoritos nesta sala" e "meus favoritos nesta conta".
    add_index :internal_chat_message_favorites, [:user_id, :room_id, :created_at],
              name: 'idx_msg_fav_user_room_created'
    add_index :internal_chat_message_favorites, [:user_id, :account_id, :created_at],
              name: 'idx_msg_fav_user_account_created'
  end
end
