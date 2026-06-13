class CreateAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_training_conversations do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.string :name, null: false
      t.string :clinic_sender_name, null: false
      t.integer :status, null: false, default: 0
      t.text :error_message

      # Progresso (alimenta a barra de status na aba "Treinamento")
      t.integer :message_count, default: 0
      t.integer :clinic_message_count, default: 0
      t.integer :patient_message_count, default: 0
      t.integer :audio_total, default: 0
      t.integer :audio_transcribed, default: 0
      t.integer :faq_count, default: 0

      # Resultado do parser (PII já mascarada) — temporário, para revisão na
      # Fase 1; purgado quando o ciclo completo (Fase 4) estiver pronto.
      t.jsonb :parsed_messages, default: []

      t.datetime :processed_at
      t.timestamps
    end

    add_index :ai_agent_training_conversations, :status
    add_index :ai_agent_training_conversations, [:account_id, :created_at]
  end
end
