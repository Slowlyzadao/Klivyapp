class CreateInternalChatMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_messages do |t|
      t.references :room,
                   null: false,
                   foreign_key: { to_table: :internal_chat_rooms, on_delete: :cascade },
                   index: true
      t.bigint  :sender_user_id        # nullable (msg system ou IA)
      t.bigint  :sender_ai_agent_id    # nullable (terreno Sprint 7)
      t.text    :content
      t.string  :content_type, null: false, default: 'text' # text | image | audio | video | file | system
      t.jsonb   :content_attributes, null: false, default: {}
      t.datetime :edited_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :internal_chat_messages, [:room_id, :created_at], order: { created_at: :desc }
    add_index :internal_chat_messages, :sender_user_id
    add_index :internal_chat_messages, :sender_ai_agent_id
    add_index :internal_chat_messages, :content_attributes, using: :gin
  end
end
