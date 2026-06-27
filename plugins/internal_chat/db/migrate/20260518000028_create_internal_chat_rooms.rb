class CreateInternalChatRooms < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_rooms do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string  :kind, null: false, default: 'direct' # direct | group
      t.string  :name
      t.text    :description
      t.string  :avatar_url
      t.bigint  :created_by_user_id
      t.datetime :last_message_at
      t.datetime :archived_at
      t.timestamps
    end

    add_index :internal_chat_rooms, [:account_id, :last_message_at], order: { last_message_at: :desc }
    add_index :internal_chat_rooms, [:account_id, :kind]
    add_index :internal_chat_rooms, :created_by_user_id
  end
end
