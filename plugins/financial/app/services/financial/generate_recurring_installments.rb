module Financial
  # Gera Budget+Installment para UM `RecurringBilling` no período corrente.
  # Chamado pelo `Financial::GenerateRecurringBillingsJob` (cron diário) para
  # cada billing ativo com `next_generation_at <= today`.
  #
  # Comportamento atômico:
  #   1. Cria Budget(status='aprovado', origin='mensalidade_recorrente',
  #      approved_at = today, payment_method copiado do billing)
  #   2. Cria 1 BudgetItem com a descrição do billing + total_cents = amount_cents
  #   3. Cria 1 Installment(status='pendente', amount_cents, payment_method_id,
  #      due_date = next_generation_at, total_in_series=1)
  #   4. Provisiona CommissionEntry se o billing tem professional + rule
  #   5. Atualiza billing.last_generated_at = now, next_generation_at += frequency
  #   6. Se billing.next_generation_at > end_date → status = 'completed'
  #
  # NÃO auto-recebe (mesmo se payment_method.settlement_mode = on_confirm) —
  # não tem operador no momento da geração (cron diário). Cartão com
  # settlement_mode=on_due_date será capturado pelo
  # `AutoSettleCardInstallmentsJob` no dia do vencimento.
  class GenerateRecurringInstallments
    Result = Financial::ServiceResult

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(recurring_billing:, today: Date.current)
      @rb = recurring_billing
      @today = today
    end

    def call
      return Result.failure('billing inativo') unless @rb.active?
      return Result.failure('billing fora da janela') if @rb.next_generation_at > @today

      budget = nil
      installment = nil

      ActiveRecord::Base.transaction do
        budget = create_budget!
        create_budget_item!(budget)
        installment = create_installment!(budget)
        provision_commission!(installment) if @rb.professional_id
        advance_billing_cycle!
      end

      Result.success(budget: budget, installment: installment, billing: @rb.reload)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    def create_budget!
      Financial::Budget.create!(
        account_id: @rb.account_id,
        patient_id: @rb.patient_id,
        professional_id: @rb.professional_id,
        status: 'aprovado',
        origin: 'mensalidade_recorrente',
        installments_count: 1,
        payment_method: @rb.payment_method.kind,
        payment_method_id: @rb.payment_method_id,
        approved_at: Time.current,
        approved_by_id: nil,  # nil = sistema (geração automática)
        notes: "Gerado por mensalidade fixa ##{@rb.id} (#{@rb.description})"
      )
    end

    def create_budget_item!(budget)
      Financial::BudgetItem.create!(
        account_id: @rb.account_id,
        financial_budget_id: budget.id,
        description: @rb.description,
        quantity: 1,
        unit_price_cents: @rb.amount_cents,
        total_cents: @rb.amount_cents
      )
    end

    def create_installment!(budget)
      Financial::Installment.create!(
        account_id: @rb.account_id,
        financial_budget_id: budget.id,
        patient_id: @rb.patient_id,
        professional_id: @rb.professional_id,
        financial_dre_category_id: dre_category_id,
        number: 1,
        total_in_series: 1,
        amount_cents: @rb.amount_cents,
        received_amount_cents: 0,
        status: 'pendente',
        payment_method: @rb.payment_method.kind,
        payment_method_id: @rb.payment_method_id,
        due_date: @rb.next_generation_at,
        competence_date: @today,
        gateway: 'manual'
      )
    end

    def dre_category_id
      @rb.financial_dre_category_id ||
        Financial::DreCategory
          .for_account(@rb.account_id)
          .where(kind: 'receita', is_default: true)
          .pick(:id) ||
        Financial::DreCategory.for_account(@rb.account_id).receitas.pick(:id)
    end

    # Provisão de comissão — copiado do ApproveBudget#provision_commissions,
    # adaptado pro caso de 1 parcela única.
    def provision_commission!(inst)
      rule = Financial::CommissionRule.most_specific_for(
        professional_id: inst.professional_id,
        date: inst.competence_date,
        category_id: inst.financial_dre_category_id
      )
      return unless rule

      cents = rule.kind == 'valor_fixo' ? rule.fixed_amount_cents.to_i
                                        : ((inst.amount_cents * rule.percent_basis_points) / 10_000.0).round

      Financial::CommissionEntry.create!(
        account_id: inst.account_id,
        professional_id: inst.professional_id,
        financial_installment_id: inst.id,
        financial_commission_rule_id: rule.id,
        status: 'provisionada',
        base_amount_cents: inst.amount_cents,
        calc_base_cents: inst.amount_cents,
        percent_basis_points: rule.percent_basis_points,
        commission_amount_cents: cents,
        competence_date: inst.competence_date
      )
    end

    # Avança o billing: marca last_generated_at, soma frequency em next_generation_at,
    # e fecha (status='completed') se passou do end_date.
    def advance_billing_cycle!
      new_next = @rb.next_after(@rb.next_generation_at)
      new_status = @rb.end_date.present? && new_next > @rb.end_date ? 'completed' : 'active'
      @rb.update!(
        last_generated_at: Time.current,
        next_generation_at: new_next,
        status: new_status
      )
    end
  end
end
