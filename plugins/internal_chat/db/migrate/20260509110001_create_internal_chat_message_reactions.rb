class CreateInternalChatMessageReactions < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_message_reactions do |t|
      t.references :user,    null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :message, null: false, foreign_key: { to_table: :internal_chat_messages, on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.bigint     :room_id, null: false
      # Emoji em UTF-8. Limit 16 acomoda emojis com modificadores (ZWJ sequences).
      t.string     :emoji, null: false, limit: 16
      t.timestamps
    end

    # WhatsApp-style: cada usuário pode ter no máximo UMA reação por mensagem.
    # Trocar de emoji vira UPDATE da mesma linha.
    # (message_id já tem index pelo t.references — agregado "reações desta msg".)
    add_index :internal_chat_message_reactions, [:user_id, :message_id], unique: true,
              name: 'idx_msg_reaction_uniq'
  end
end
