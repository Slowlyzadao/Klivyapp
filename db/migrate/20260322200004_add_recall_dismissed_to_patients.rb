class AddRecallDismissedToPatients < ActiveRecord::Migration[7.1]
  def change
    add_column :patients, :recall_dismissed_at, :datetime
    add_column :patients, :recall_dismissed_by_id, :bigint

    add_index :patients, :recall_dismissed_at, where: 'recall_dismissed_at IS NOT NULL',
                                                name: 'idx_patients_recall_dismissed'
  end
end
