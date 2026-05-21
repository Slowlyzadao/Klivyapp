module Patients
  class UpdateTreatmentPlanStatusJob < ApplicationJob
    queue_as :default

    def perform(treatment_plan_id)
      plan = TreatmentPlan.find_by(id: treatment_plan_id)
      return unless plan

      Patients::TreatmentPlanStatusUpdater.new(plan).call
    end
  end
end
