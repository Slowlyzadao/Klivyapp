class CreateAiAgentToolDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_tool_definitions do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :enabled_globally, null: false, default: true
      t.boolean :requires_oauth, null: false, default: false
      t.boolean :builtin, null: false, default: false
      t.jsonb :config_schema, null: false, default: {}
      t.timestamps
    end

    add_index :ai_agent_tool_definitions, :key, unique: true
    add_index :ai_agent_tool_definitions, :enabled_globally
  end
end
