class CreateCriticalAlerts < ActiveRecord::Migration[7.0]
  def change
    create_table :critical_alerts do |t|
      t.bigint  :account_id,   null: false
      t.bigint  :patient_id,   null: false
      t.string  :alert_type,   null: false  # allergy / condition / medication / other
      t.string  :severity,     null: false, default: 'high'  # high / medium / low
      t.string  :title,        null: false
      t.text    :description
      t.boolean :active,       default: true
      t.bigint  :created_by_id
      t.datetime :deleted_at
      t.timestamps null: false
    end

    add_index :critical_alerts, :patient_id
    add_index :critical_alerts, :account_id
    add_index :critical_alerts, [:patient_id, :active]
    add_index :critical_alerts, :deleted_at

    add_foreign_key :critical_alerts, :accounts
    add_foreign_key :critical_alerts, :patients
  end
end
