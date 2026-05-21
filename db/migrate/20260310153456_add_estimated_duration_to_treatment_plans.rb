class AddEstimatedDurationToTreatmentPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :treatment_plans, :estimated_duration, :string
  end
end
