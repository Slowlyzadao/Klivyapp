class CreateTreatmentPlans < ActiveRecord::Migration[7.0]
  def change
    create_table :treatment_plans do |t|
      t.bigint  :account_id,          null: false
      t.bigint  :patient_id,          null: false
      t.bigint  :professional_id
      t.string  :title
      t.text    :description
      t.string  :status,              null: false, default: 'proposto'
      # proposto / aprovado / em_execucao / concluido / cancelado
      t.boolean :partially_approved,  null: false, default: false
      t.date    :approved_at
      t.bigint  :approved_by_id
      t.text    :cancellation_reason
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :treatment_plans, :account_id
    add_index :treatment_plans, :patient_id
    add_index :treatment_plans, :professional_id
    add_index :treatment_plans, :status
    add_index :treatment_plans, :deleted_at
  end
end
