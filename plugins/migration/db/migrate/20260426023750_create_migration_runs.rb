class CreateMigrationRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :migration_runs do |t|
      t.bigint  :account_id, null: false
      t.string  :kind,       null: false
      t.string  :status,     null: false, default: 'pending'
      t.string  :source,     null: false, default: 'clinicorp'
      t.string  :csv_filename
      t.integer :total_rows,    default: 0
      t.integer :processed_rows, default: 0
      t.integer :created_count,  default: 0
      t.integer :updated_count,  default: 0
      t.integer :skipped_count,  default: 0
      t.integer :error_count,    default: 0
      t.jsonb   :errors_log,     default: []
      t.text    :error_message
      t.bigint  :triggered_by_super_admin_id
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :migration_runs, :account_id
    add_index :migration_runs, [:account_id, :kind]
    add_index :migration_runs, :status
  end
end
