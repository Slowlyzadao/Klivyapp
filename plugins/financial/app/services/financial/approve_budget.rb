module Financial
  # Aprova um orçamento e gera as parcelas em A Receber.
  # Cadeia de efeitos (canon backlog Parte I §2.2):
  #   1. status do Budget → aprovado
  #   2. gerar N parcelas com distribuição de centavos canônica
  #   3. para cada parcela, criar charge no gateway (se não-manual)
  #   4. provisionar comissão (CommissionEntry) se há regra para o profissional
  #   5. atualizar timestamp approved_at + approved_by_id
  #
  # Tudo em ActiveRecord::Base.transaction. Falha em qualquer passo desfaz tudo.
  class ApproveBudget
    Result = Financial::ServiceResult

    # @param budget [Financial::Budget]
    # @param actor  [User]
    # @param installments_plan [Array<Hash>] opcional — sobrescreve a divisão canon.
    #   Cada item: { amount_cents:, due_date:, payment_method:, professional_id?: }
    # @param payment_method [String] forma default das parcelas
    # @param first_due_date [Date]
    # @param interval_days  [Integer] default 30
    # @return [Result]
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(budget:, actor:, installments_plan: nil, payment_method: nil,
                   first_due_date: nil, interval_days: 30)
      @budget = budget
      @actor = actor
      @plan = installments_plan
      @payment_method = payment_method || budget.payment_method || 'pix'
      # Coerção: vem como String do params do controller (ISO 'YYYY-MM-DD');
      # precisamos de Date para `+ (n).days` aritmética funcionar.
      @first_due_date = parse_date(first_due_date) || Date.current
      @interval_days = interval_days.to_i
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def call
      return Result.failure('Orçamento já aprovado') if @budget.approved?
      return Result.failure('Orçamento cancelado não pode ser aprovado') if @budget.canceled?
      return Result.failure('Orçamento não tem total > 0') if @budget.total_cents.to_i <= 0

      installments = nil

      ActiveRecord::Base.transaction do
        @budget.update!(
          status: 'aprovado',
          approved_at: Time.current,
          approved_by_id: @actor&.id
        )

        installments = generate_installments
        provision_commissions(installments) if installments.any?
        sync_with_gateway(installments)
      end

      Result.success(budget: @budget.reload, installments: installments)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    # Gera N parcelas. Distribui centavos: resto na ÚLTIMA (canon Parte 6).
    def generate_installments
      plan = @plan.presence || build_default_plan

      plan.each_with_index.map do |row, idx|
        @budget.installments.create!(
          account_id: @budget.account_id,
          patient_id: @budget.patient_id,
          professional_id: row[:professional_id] || @budget.professional_id,
          financial_dre_category_id: default_revenue_category_id,
          number: idx + 1,
          total_in_series: plan.size,
          amount_cents: row[:amount_cents],
          received_amount_cents: 0,
          status: 'pendente',
          payment_method: row[:payment_method] || @payment_method,
          due_date: row[:due_date],
          competence_date: @budget.approved_at.to_date,
          gateway: gateway_name
        )
      end
    end

    def build_default_plan
      n = @budget.installments_count
      pieces = Financial::Concerns::MoneyAttribute.split(@budget.total_cents, n)
      pieces.each_with_index.map do |amount_cents, idx|
        {
          amount_cents: amount_cents,
          due_date: @first_due_date + (@interval_days * idx).days,
          payment_method: @payment_method
        }
      end
    end

    def default_revenue_category_id
      Financial::DreCategory
        .for_account(@budget.account_id)
        .where(kind: 'receita', is_default: true)
        .pick(:id) ||
        Financial::DreCategory.for_account(@budget.account_id).receitas.pick(:id)
    end

    def provision_commissions(installments)
      installments.each do |inst|
        next unless inst.professional_id

        rule = Financial::CommissionRule.most_specific_for(
          professional_id: inst.professional_id,
          date: inst.competence_date,
          category_id: inst.financial_dre_category_id
        )
        next unless rule

        # Provisão = base bruta sem deduções (calc_base = base_amount).
        Financial::CommissionEntry.create!(
          account_id: inst.account_id,
          professional_id: inst.professional_id,
          financial_installment_id: inst.id,
          financial_commission_rule_id: rule.id,
          status: 'provisionada',
          base_amount_cents: inst.amount_cents,
          calc_base_cents: inst.amount_cents,
          percent_basis_points: rule.percent_basis_points,
          commission_amount_cents: provisional_commission_cents(rule, inst.amount_cents),
          competence_date: inst.competence_date
        )
      end
    end

    def provisional_commission_cents(rule, base_cents)
      if rule.kind == 'valor_fixo'
        rule.fixed_amount_cents.to_i
      else
        ((base_cents * rule.percent_basis_points) / 10_000.0).round
      end
    end

    def sync_with_gateway(installments)
      return if gateway_name == 'manual'

      adapter = Financial::Gateways.adapter_for(@budget.account)
      return if adapter.manual?

      installments.each do |inst|
        result = adapter.create_charge(
          installment: inst,
          patient: @budget.patient,
          payment_method: inst.payment_method
        )
        next if result.failed?

        inst.update_columns(
          gateway_id: result.data[:gateway_id],
          gateway_status: result.data[:gateway_status],
          payment_link: result.data[:payment_link],
          barcode_line: result.data[:barcode_line],
          pix_qr_code: result.data[:pix_qr_code],
          pix_qr_code_image_url: result.data[:pix_qr_code_image_url],
          gateway_synced_at: Time.current,
          updated_at: Time.current
        )
      end
    end

    def gateway_name
      @gateway_name ||= Financial::GatewaySetting.find_by(account_id: @budget.account_id)&.gateway || 'manual'
    end
  end
end
