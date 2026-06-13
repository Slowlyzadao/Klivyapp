module Financial
  # Simula o efeito financeiro de um `installments_plan` ANTES de aprovar
  # o orçamento. Read-only — não persiste nada, não dispara AuditLog, não
  # toca em CommissionEntry/Entry/Installment. Apenas projeta:
  #
  #   - Taxa (fee) por parcela: lookup em `PaymentMethodFee` vigente
  #     usando `installments_count = plan.size` (canon — casa com o
  #     `ReceivePayment#freeze_payment_fee_snapshot!` que usa total_in_series).
  #   - Valor líquido por parcela: `amount_cents - fee_amount_cents`.
  #   - Data esperada de liquidação: `due_date + liquidation_days`.
  #   - Comissão estimada: `CommissionRule.most_specific_for` aplicado sobre
  #     a base configurada (bruto/recebido/recebido_menos_mdr). Best-effort —
  #     base `recebido_menos_lab` ignora lab porque a simulação não tem
  #     contexto de despesa de laboratório ainda.
  #
  # Usado pelo `PaymentPlanWizardV2` (frontend) via
  # `POST /budgets/:id/simulate_plan` para mostrar bruto × taxa × líquido +
  # comissão estimada antes do operador confirmar a aprovação.
  #
  # Não é a fonte de verdade do recebimento — o snapshot real é congelado
  # em `Installment` no momento da aprovação via `ApproveBudget` e no
  # momento do recebimento via `ReceivePayment#freeze_payment_fee_snapshot!`.
  # Mudanças de fee entre simulação e aprovação são possíveis (vigência
  # nova entrou em vigor); UI deve avisar se discrepância for detectada.
  class SimulatePaymentPlan
    Result = Financial::ServiceResult

    # @param budget [Financial::Budget]
    # @param installments_plan [Array<Hash>] cada item:
    #   { amount_cents:, due_date:, payment_method:, payment_method_id?:, professional_id?: }
    # @return [Financial::ServiceResult]
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(budget:, installments_plan:)
      @budget = budget
      @plan = Array(installments_plan)
    end

    def call
      return Result.failure('installments_plan vazio') if @plan.empty?

      total_in_series = @plan.size
      rows = @plan.each_with_index.map { |item, idx| build_row(item, idx, total_in_series) }
      totals = aggregate_totals(rows)

      Result.success(plan: rows, totals: totals)
    end

    private

    def build_row(item, idx, total_in_series)
      # Wizard manda `amount_cents` como BASE (= quanto clínica deve receber em líquido).
      # Quando o método repassa MDR ao paciente, o valor que o paciente paga
      # é maior — calculado via `PaymentMethodFee#inflate_amount_cents`.
      # Quando absorve (canon V2 original), paciente paga o próprio base e
      # clínica recebe `base - fee`.
      base_cents = item[:amount_cents].to_i
      due_date = parse_date(item[:due_date]) || Date.current
      pm = resolve_payment_method(item[:payment_method_id], item[:payment_method])
      # MDR é por TRANSAÇÃO: numa divisão multi-cartão, cada perna tem seu
      # próprio parcelamento na maquininha (`card_installments`). Sem isso a
      # taxa era buscada com `total_in_series` (tamanho do plano) pra todas as
      # pernas — mentia o líquido de "Cielo 3x + Stone 1x". Fallback no plano.
      lookup_count = item[:card_installments].to_i.positive? ? item[:card_installments].to_i : total_in_series
      fee = pm&.fee_for(installments_count: lookup_count, on_date: due_date)
      passes = pm&.passes_fee_to_patient == true

      if passes && fee
        amount_for_patient_cents = fee.inflate_amount_cents(base_cents)
        fee_cents = amount_for_patient_cents - base_cents
        net_cents = base_cents  # clínica recebe o base cheio
      else
        amount_for_patient_cents = base_cents
        fee_cents = fee ? fee.calculate_fee_cents(base_cents) : 0
        net_cents = base_cents - fee_cents
      end

      professional_id = item[:professional_id].presence || @budget.professional_id
      expected_commission_cents = estimate_commission(
        professional_id: professional_id,
        amount_cents: net_cents,  # comissão sobre o que clínica de fato recebe
        fee_cents: fee_cents,
        date: due_date
      )

      {
        row_index: idx,
        # `amount_cents` mantém a semântica de "valor da Installment que vai pra
        # cobrança" (= o que paciente paga). No modelo passthrough, é o inflado.
        amount_cents: amount_for_patient_cents,
        # `base_amount_cents` é o que clínica de fato recebe líquido.
        # Sempre igual ao `amount_cents` quando NÃO há repasse.
        base_amount_cents: net_cents,
        # `amount_for_patient_cents` é alias explícito para frontend não precisar
        # se preocupar com o modelo (passthrough vs absorb).
        amount_for_patient_cents: amount_for_patient_cents,
        passes_fee_to_patient: passes,
        payment_method: item[:payment_method] || pm&.kind,
        payment_method_id: pm&.id,
        payment_method_name: pm&.name,
        fee_percent_basis_points: fee&.fee_percent_basis_points.to_i,
        fee_fixed_cents: fee&.fee_fixed_cents.to_i,
        fee_amount_cents: fee_cents,
        net_amount_cents: net_cents,
        liquidation_days: fee&.liquidation_days.to_i,
        expected_liquidation_date: due_date + fee&.liquidation_days.to_i.days,
        due_date: due_date,
        professional_id: professional_id,
        expected_commission_cents: expected_commission_cents,
        fee_resolved: !fee.nil?
      }
    end

    # Resolve PaymentMethod por id (preferencial — refactor 2026-05-25) ou
    # por kind (fallback compat). Sempre scoped por account do budget.
    def resolve_payment_method(pm_id, pm_kind)
      scope = ::Financial::PaymentMethod.for_account(@budget.account_id).alive

      if pm_id.present?
        scope.find_by(id: pm_id)
      elsif pm_kind.present?
        scope.where(kind: pm_kind, status: 'active').order(:id).first
      end
    end

    # Aplica regra mais específica do profissional sobre a base configurada.
    # Best-effort: `recebido_menos_lab` tratado como `recebido` porque a
    # simulação não tem contexto de despesa de laboratório por parcela.
    def estimate_commission(professional_id:, amount_cents:, fee_cents:, date:)
      return 0 if professional_id.blank?

      rule = ::Financial::CommissionRule.most_specific_for(
        professional_id: professional_id, date: date
      )
      return 0 if rule.nil?

      base_cents = case rule.base
                   when 'recebido_menos_mdr' then amount_cents - fee_cents
                   else amount_cents
                   end

      if rule.kind == 'valor_fixo'
        rule.fixed_amount_cents.to_i
      else
        (base_cents * rule.percent_basis_points.to_i / 10_000.0).round
      end
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def aggregate_totals(rows)
      {
        # `gross_cents` = quanto paciente paga no total (mesmo do `amount_cents` da Installment).
        gross_cents:                rows.sum { |r| r[:amount_cents] },
        total_fee_cents:            rows.sum { |r| r[:fee_amount_cents] },
        # `total_net_cents` = quanto cai na conta da clínica (= soma das `base_amount_cents`).
        total_net_cents:            rows.sum { |r| r[:net_amount_cents] },
        # `total_base_cents` = mesma coisa que `total_net_cents` — alias semântico.
        total_base_cents:           rows.sum { |r| r[:base_amount_cents] },
        # `total_amount_for_patient_cents` = explicitamente "quanto paciente paga".
        # No modelo absorb é igual a `gross_cents`; no passthrough também é igual,
        # mas o nome explícito facilita o frontend sem precisar inferir o modelo.
        total_amount_for_patient_cents: rows.sum { |r| r[:amount_for_patient_cents] },
        expected_commission_cents:  rows.sum { |r| r[:expected_commission_cents] },
        installments_count:         rows.size,
        all_fees_resolved:          rows.all? { |r| r[:fee_resolved] },
        # Flag global: pelo menos uma linha está em passthrough? UI usa pra
        # decidir se mostra coluna extra "Cliente paga" diferente de "Valor base".
        has_passthrough_rows:       rows.any? { |r| r[:passes_fee_to_patient] }
      }
    end
  end
end
