# app/services/patients/financial_estimate_generator.rb
#
# SERVICE: FinancialEstimateGenerator
#
# Propósito: Chamado pelo TreatmentPlanApprover após aprovação do plano.
#   Cria automaticamente um FinancialEstimate com todas as transações/parcelas
#   baseadas nos TreatmentItems aprovados.
#
# Uso:
#   result = Patients::FinancialEstimateGenerator.call(
#     treatment_plan: plan,
#     actor: current_user,
#     installments_count: 3,      # opcional (default: 1)
#     payment_method: 'pix'       # opcional
#   )
#   result.success?   # true/false
#   result.estimate   # FinancialEstimate criado
#   result.error      # mensagem de erro se falhou

module Patients
  class FinancialEstimateGenerator
    Result = Struct.new(:success?, :estimate, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(treatment_plan:, actor:, installments_count: 1, payment_method: nil)
      @plan = treatment_plan
      @actor = actor
      @installments_count = installments_count.to_i.clamp(1, 60)
      @payment_method = payment_method
    end

    def call
      ActiveRecord::Base.transaction do
        estimate = build_estimate
        estimate.save!

        Result.new(success?: true, estimate: estimate, error: nil)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, estimate: nil, error: e.message)
    rescue StandardError => e
      Rails.logger.error("[FinancialEstimateGenerator] Erro: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      Result.new(success?: false, estimate: nil, error: e.message)
    end

    private

    def build_estimate
      approved_items = @plan.treatment_items.where(
        status: %w[aprovado em_execucao proposto]
      )

      subtotal = approved_items.sum(:total_price)

      FinancialEstimate.new(
        account_id: @plan.account_id,
        patient_id: @plan.patient_id,
        treatment_plan_id: @plan.id,
        generated_by_id: @actor.id,
        status: 'rascunho',
        subtotal: subtotal,
        discount_amount: 0.0,
        total: subtotal,
        installments_count: @installments_count,
        payment_method: @payment_method,
        valid_until: 30.days.from_now.to_date,
        notes: "Orçamento gerado automaticamente a partir do Plano de Tratamento ##{@plan.id}"
      )
    end


  end
end
