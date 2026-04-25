module Patients
  # Aprova um TreatmentPlan (inteiro ou parcialmente).
  # Após aprovação, chama FinancialEstimateGenerator (Bloco 4) para criar
  # automaticamente o orçamento financeiro vinculado ao plano.
  #
  # Uso:
  #   result = Patients::TreatmentPlanApprover.new(plan, approved_by: current_user).call
  #   result.success?         => true/false
  #   result.plan             => plano atualizado
  #   result.financial_estimate => FinancialEstimate gerado (pode ser nil se falhou)
  #   result.error            => mensagem de erro (se falhou)
  class TreatmentPlanApprover
    Result = Struct.new(:success?, :plan, :financial_estimate, :error, keyword_init: true)

    def initialize(plan, approved_by:, item_ids: nil, installments_count: 1, payment_method: nil)
      @plan               = plan
      @approved_by        = approved_by
      @item_ids           = item_ids  # nil = aprovar tudo; array = aprovação parcial
      @installments_count = installments_count
      @payment_method     = payment_method
    end

    def call
      return Result.new(success?: false, plan: @plan, financial_estimate: nil, error: 'Plano não está em status proposto') \
        unless @plan.status_proposto?

      financial_estimate = nil

      ActiveRecord::Base.transaction do
        if @item_ids.present?
          approve_partial!
        else
          approve_all!
        end

        @plan.update!(
          approved_by: @approved_by,
          approved_at: Date.current
        )

        # Gera o FinancialEstimate automaticamente após aprovação
        estimate_result = Patients::FinancialEstimateGenerator.call(
          treatment_plan: @plan,
          actor: @approved_by,
          installments_count: @installments_count,
          payment_method: @payment_method
        )

        financial_estimate = estimate_result.estimate if estimate_result.success?

        Rails.logger.warn("[TreatmentPlanApprover] FinancialEstimateGenerator falhou: #{estimate_result.error}") \
          unless estimate_result.success?

        # Generate PDF for the approved plan
        Patients::TreatmentPlanPdfGenerator.call(
          treatment_plan: @plan,
          actor: @approved_by
        )
      end

      Result.new(success?: true, plan: @plan.reload, financial_estimate: financial_estimate, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, plan: @plan, financial_estimate: nil, error: e.message)
    end

    private

    def approve_all!
      @plan.treatment_items.where(deleted_at: nil, status: 'proposto').update_all(status: 'aprovado')
      @plan.update!(status: 'aprovado', partially_approved: false)
    end

    def approve_partial!
      @plan.treatment_items
           .where(deleted_at: nil, id: @item_ids, status: 'proposto')
           .update_all(status: 'aprovado')

      all_ids = @plan.treatment_items.where(deleted_at: nil).pluck(:id)
      approved_ids = @plan.treatment_items.where(deleted_at: nil, status: 'aprovado').pluck(:id)
      partially = (all_ids - approved_ids).any?

      @plan.update!(status: 'aprovado', partially_approved: partially)
    end
  end
end
