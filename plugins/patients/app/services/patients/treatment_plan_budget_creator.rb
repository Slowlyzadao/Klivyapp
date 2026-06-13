# frozen_string_literal: true

module Patients
  # Cria um `Financial::Budget` (v2) em status RASCUNHO a partir de um
  # `TreatmentPlan` que acabou de ser aprovado clinicamente. Substitui o v1
  # `Patients::FinancialEstimateGenerator` (deletado em 2026-05-11) — mesmo
  # papel, alimentando `financial_*`.
  #
  # IMPORTANTE — fluxo 2-step deliberado:
  #   Aprovar plano (dentista, clínico) → Budget RASCUNHO com items + totais
  #   Recepção valida no Financial Tab → clica "Aprovar orçamento" (rota v2
  #   `POST /financial/v2/budgets/:id/approve`) → ApproveBudget v2 gera as
  #   parcelas em A Receber, provisiona comissão, sincroniza com gateway.
  #
  # NÃO chamamos `Financial::ApproveBudget` aqui — esse passo fica com a
  # recepção pra preservar a separação clínica/financeira do v1 antigo
  # (decisão Mamedes 2026-05-11). Dentista define preços do plano, recepção
  # valida ajustes (parcelamento, método de pagamento) antes de gerar A Receber.
  #
  # Pipeline:
  #   1. Cria Budget RASCUNHO (origin: `plano_tratamento`, FK pro TreatmentPlan)
  #   2. Cria BudgetItem por TreatmentItem aprovado (procedure_name → description,
  #      unit_price → unit_price_cents, sessions_planned → quantity)
  #   3. Recalcula subtotal/discount/total
  #
  # Uso:
  #   result = Patients::TreatmentPlanBudgetCreator.call(
  #     treatment_plan: @plan,
  #     actor: current_user,
  #     installments_count: 3,
  #     payment_method: 'pix'
  #   )
  #   result.success?  # => true/false
  #   result.budget    # => Financial::Budget rascunho (ou nil em erro)
  #   result.error     # => mensagem (ou nil em sucesso)
  class TreatmentPlanBudgetCreator
    Result = Struct.new(:success?, :budget, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(treatment_plan:, actor:, installments_count: 1,
                   payment_method: nil)
      @plan = treatment_plan
      @actor = actor
      @installments_count = installments_count.to_i.clamp(1, 60)
      @payment_method = payment_method.presence
    end

    def call
      return Result.new(success?: false, budget: nil, error: 'Plano deve estar aprovado') \
        unless @plan.status_aprovado?

      approved_items = @plan.treatment_items.active.where(status: 'aprovado')
      return Result.new(success?: false, budget: nil, error: 'Plano não tem itens aprovados') \
        if approved_items.empty?

      budget = nil
      ActiveRecord::Base.transaction do
        budget = build_budget!
        build_items!(budget, approved_items)
        recalc_totals!(budget)
      end

      Result.new(success?: true, budget: budget, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, budget: nil, error: e.message)
    end

    private

    def build_budget!
      Financial::Budget.create!(
        account: @plan.account,
        patient: @plan.patient,
        professional: @plan.professional,
        treatment_plan: @plan,
        origin: 'plano_tratamento',
        status: 'rascunho',
        installments_count: @installments_count,
        payment_method: @payment_method,
        notes: build_notes
      )
    end

    def build_notes
      title = @plan.title.presence || "##{@plan.id}"
      "Gerado automaticamente da aprovação do plano de tratamento #{title}"
    end

    def build_items!(budget, treatment_items)
      treatment_items.find_each do |ti|
        unit_cents = ((ti.unit_price || 0).to_f * 100).round
        qty = (ti.sessions_planned || 1).to_i
        Financial::BudgetItem.create!(
          account: budget.account,
          budget: budget,
          treatment_item: ti,
          description: ti.procedure_name.to_s[0, 240],
          quantity: qty.positive? ? qty : 1,
          unit_price_cents: unit_cents,
          discount_cents: discount_cents_for(ti, unit_cents, qty)
        )
      end
    end

    # Mapeia desconto do TreatmentItem (decimal R$ + tipo percentual/fixo) pra
    # centavos absolutos no BudgetItem.
    def discount_cents_for(item, unit_cents, qty)
      value = item.discount_value.to_f
      return 0 if value <= 0

      base = unit_cents * qty
      case item.discount_type
      when 'percentual' then (base * value / 100).round
      when 'fixo'       then (value * 100).round
      else 0
      end
    end

    def recalc_totals!(budget)
      items = budget.items.reload
      subtotal = items.sum { |i| i.unit_price_cents.to_i * i.quantity.to_i }
      discount = items.sum { |i| i.discount_cents.to_i }
      budget.update!(
        subtotal_cents: subtotal,
        discount_cents: discount,
        total_cents:    subtotal - discount
      )
    end
  end
end
