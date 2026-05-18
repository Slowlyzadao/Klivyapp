class AddLastConsolidatedAtToPatientMemories < ActiveRecord::Migration[7.1]
  def change
    # Marca quando o Distiller rodou pela última vez. Job pula memórias
    # consolidadas nas últimas 23h pra evitar reconsolidar mesmo paciente
    # várias vezes por dia se cron rodar mais de uma vez.
    add_column :ai_agent_patient_memories, :last_consolidated_at, :datetime, null: true
    add_index :ai_agent_patient_memories, :last_consolidated_at
  end
end
