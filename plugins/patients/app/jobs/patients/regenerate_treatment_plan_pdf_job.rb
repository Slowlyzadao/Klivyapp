# frozen_string_literal: true

# Regenera o PDF de um TreatmentPlan que já teve um PDF anexado anteriormente.
# Disparado por callbacks em TreatmentPlan e TreatmentItem quando o conteúdo
# muda após a primeira geração (ex: novo procedimento adicionado, valor
# editado, item removido). Active Storage purga o blob antigo no R2
# automaticamente ao re-`attach`.
module Patients
  class RegenerateTreatmentPlanPdfJob < ApplicationJob
    queue_as :default

    def perform(treatment_plan_id)
      plan = TreatmentPlan.find_by(id: treatment_plan_id, deleted_at: nil)
      return unless plan
      return unless plan.pdf.attached?
      return if plan.status_cancelado?

      Patients::TreatmentPlanPdfGenerator.call(
        treatment_plan: plan,
        actor: plan.approved_by || plan.professional
      )
    end
  end
end
