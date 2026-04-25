module Patients
  class IncrementTreatmentSessionJob < ApplicationJob
    queue_as :default

    def perform(treatment_item_id)
      item = TreatmentItem.find_by(id: treatment_item_id)
      return unless item

      item.increment_sessions_done!
    end
  end
end
