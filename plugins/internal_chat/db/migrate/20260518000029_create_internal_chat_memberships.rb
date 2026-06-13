class CreateInternalChatMemberships < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_memberships do |t|
      t.references :room,
                   null: false,
                   foreign_key: { to_table: :internal_chat_rooms, on_delete: :cascade },
                   index: true
      t.bigint  :user_id          # nullable (membro humano)
      t.bigint  :ai_agent_id      # nullable (Bea / IA — preparado para Sprint 7)
      t.string  :role, null: false, default: 'member' # owner | admin | member
      t.bigint  :last_read_message_id
      t.datetime :muted_until
      t.datetime :joined_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.datetime :left_at
      t.timestamps
    end

    add_index :internal_chat_memberships, [:room_id, :user_id], unique: true,
                                                                where: 'user_id IS NOT NULL',
                                                                name: 'idx_unique_membership_user'
    add_index :internal_chat_memberships, [:room_id, :ai_agent_id], unique: true,
                                                                    where: 'ai_agent_id IS NOT NULL',
                                                                    name: 'idx_unique_membership_ai_agent'
    add_index :internal_chat_memberships, :user_id
    add_index :internal_chat_memberships, :ai_agent_id

    # Garante exatamente um de user_id ou ai_agent_id preenchido
    execute <<~SQL.squish
      ALTER TABLE internal_chat_memberships
      ADD CONSTRAINT internal_chat_memberships_member_check
      CHECK ((user_id IS NOT NULL AND ai_agent_id IS NULL)
          OR (user_id IS NULL AND ai_agent_id IS NOT NULL))
    SQL
  end
end
