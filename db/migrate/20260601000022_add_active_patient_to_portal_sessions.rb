# Sprint I — sessões ganham "acting" + "active" distintos.
#
# Antes:  `patient_id` = único paciente da sessão. Quem loga = quem vê.
# Depois: `patient_id` continua sendo o LOGADO (acting); `active_patient_id`
#         aponta pra quem ele está acessando *agora* (self ou dependente).
#
# Para sessões antigas, populamos active_patient_id = patient_id (compatível
# com fluxo single-patient). Não introduz mudança de comportamento existente.
class AddActivePatientToPortalSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :patient_portal_sessions, :active_patient_id, :bigint
    add_index  :patient_portal_sessions, :active_patient_id

    # Compatibilidade com sessões já existentes (todas eram self-access).
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE patient_portal_sessions
             SET active_patient_id = patient_id
           WHERE active_patient_id IS NULL
        SQL
      end
    end

    change_column_null :patient_portal_sessions, :active_patient_id, false
  end
end
