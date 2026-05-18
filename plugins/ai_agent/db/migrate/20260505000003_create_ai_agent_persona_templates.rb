class CreateAiAgentPersonaTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_persona_templates do |t|
      t.string :name, null: false
      t.string :vertical, null: false, default: 'general'
      t.text :system_prompt, null: false
      t.jsonb :tone_settings, null: false, default: {}
      t.jsonb :few_shot_examples, null: false, default: []
      t.boolean :builtin, null: false, default: false
      t.timestamps
    end

    add_index :ai_agent_persona_templates, :name, unique: true
    add_index :ai_agent_persona_templates, :vertical
  end
end
