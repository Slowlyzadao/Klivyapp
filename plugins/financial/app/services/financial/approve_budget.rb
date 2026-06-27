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
                   payment_method_id: nil, first_due_date: nil, interval_days: 30)
      @budget = budget
      @actor = actor
      @plan = installments_plan
      @payment_method = payment_method || budget.payment_method || 'pix'
      # Refactor 2026-05-25: PaymentMethod específico do Settings. Propagado
      # pra cada Installment gerada (a menos que custom plan defina por parcela).
      # Override pelo param do controller; fallback pro próprio Budget.
      @payment_method_id = payment_method_id || budget.payment_method_id
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

      # Fora da transação: pernas à vista (settlement_mode=on_confirm — PIX/
      # dinheiro/débito) já entram recebidas, porque o operador confirmou o
      # recebimento aqui e agora. Best-effort: se falhar (sem conta destino,
      # caixa fechado), a perna fica pendente e o operador recebe manual —
      # NÃO derruba a aprovação que já foi commitada.
      auto_receive_on_confirm_legs(installments)

      Result.success(budget: @budget.reload, installments: installments)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    # Gera N parcelas. Distribui centavos: resto na ÚLTIMA (canon Parte 6).
    #
    # F2.5: quando o PaymentMethod da row tem `passes_fee_to_patient = true`,
    # o `amount_cents` enviado pelo wizard é interpretado como BASE (o que a
    # clínica recebe) e inflado para o valor que o paciente vai pagar de fato.
    # Caller que mande row sem flag (= absorve) continua salvando o amount cru.
    def generate_installments
      plan = @plan.presence || build_default_plan
      total_in_series = plan.size

      plan.each_with_index.map do |row, idx|
        pm_id = row[:payment_method_id] || @payment_method_id
        due_date = row[:due_date]
        # Parcelamento DESSA perna na maquininha (multi-cartão). Fallback no
        # tamanho do plano — usado tanto p/ inflar (passthrough) quanto p/ o
        # snapshot de MDR no recebimento.
        card_installments = row[:card_installments].to_i.positive? ? row[:card_installments].to_i : nil
        lookup_count = card_installments || total_in_series
        amount_cents = compute_installment_amount(
          base_cents: row[:amount_cents],
          payment_method_id: pm_id,
          installments_count: lookup_count,
          on_date: due_date
        )

        @budget.installments.create!(
          account_id: @budget.account_id,
          patient_id: @budget.patient_id,
          professional_id: row[:professional_id] || @budget.professional_id,
          financial_dre_category_id: default_revenue_category_id,
          number: idx + 1,
          total_in_series: total_in_series,
          amount_cents: amount_cents,
          received_amount_cents: 0,
          status: 'pendente',
          payment_method: row[:payment_method] || @payment_method,
          # Refactor 2026-05-25: propaga payment_method_id do row (custom plan)
          # ou do default do budget. Permite rastreabilidade do PaymentMethod
          # específico sugerido em cada parcela desde o momento da aprovação.
          payment_method_id: pm_id,
          # Pagamento dividido (2026-05-27): parcelamento da perna + grupo do
          # tender (pernas pagas no mesmo momento, ex.: PIX + 2 cartões).
          card_installments: card_installments,
          tender_group: row[:tender_group].presence,
          due_date: due_date,
          competence_date: @budget.approved_at.to_date,
          gateway: gateway_name
        )
      end
    end

    # F2.5 — Decide se infla o amount_cents conforme a flag `passes_fee_to_patient`
    # do PaymentMethod referenciado. Quando flag = false (canon V2), retorna o
    # base cru. Quando true, calcula via `PaymentMethodFee#inflate_amount_cents`
    # de modo que `amount - fee = base` (clínica recebe o base cheio).
    #
    # Sem PaymentMethod ou sem fee vigente → não infla (best-effort).
    def compute_installment_amount(base_cents:, payment_method_id:, installments_count:, on_date:)
      return base_cents.to_i if payment_method_id.blank?

      pm = ::Financial::PaymentMethod
             .for_account(@budget.account_id)
             .alive
             .find_by(id: payment_method_id)
      return base_cents.to_i if pm.nil? || !pm.passes_fee_to_patient

      fee = pm.fee_for(installments_count: installments_count, on_date: on_date)
      return base_cents.to_i if fee.nil?

      inflated = fee.inflate_amount_cents(base_cents.to_i)
      inflated.positive? ? inflated : base_cents.to_i
    end

    def build_default_plan
      n = @budget.installments_count
      pieces = Financial::Concerns::MoneyAttribute.split(@budget.total_cents, n)
      pieces.each_with_index.map do |amount_cents, idx|
        {
          amount_cents: amount_cents,
          due_date: @first_due_date + (@interval_days * idx).days,
          payment_method: @payment_method,
          payment_method_id: @payment_method_id
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

    # Pernas à vista (settlement_mode=on_confirm): recebe na hora via
    # ReceivePayment, com o operador (actor) como quem confirmou. Best-effort
    # por perna — falha de uma não afeta a aprovação nem as outras.
    #
    # Requer conta destino: usa a `default_bank_account` da forma de pagamento.
    # Sem conta configurada, deixa pendente (operador recebe manual escolhendo
    # a conta) — não chuta conta pra não alocar dinheiro no lugar errado.
    def auto_receive_on_confirm_legs(installments)
      Array(installments).each do |inst|
        pm = resolve_payment_method_record(inst.payment_method_id)
        next unless pm&.settle_on_confirm?

        bank = pm.default_bank_account
        next unless bank&.active

        result = Financial::ReceivePayment.call(
          account: @budget.account,
          actor: @actor,
          bank_account: bank,
          installment_amounts: [{ installment_id: inst.id, amount_cents: inst.amount_cents }],
          payment_method: inst.payment_method,
          payment_method_record: pm,
          received_at: @budget.approved_at.to_date
        )

        next if result.success?

        Rails.logger.warn(
          "[Financial::ApproveBudget] auto-receive on_confirm falhou inst=#{inst.id} " \
          "account=#{@budget.account_id}: #{result.errors.join('; ')}"
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[Financial::ApproveBudget] auto-receive on_confirm erro inst=#{inst.id} " \
          "account=#{@budget.account_id}: #{e.message}"
        )
      end
    end

    def resolve_payment_method_record(pm_id)
      return nil if pm_id.blank?

      @pm_cache ||= {}
      return @pm_cache[pm_id] if @pm_cache.key?(pm_id)

      @pm_cache[pm_id] = Financial::PaymentMethod
                           .for_account(@budget.account_id)
                           .alive
                           .find_by(id: pm_id)
    end

    def gateway_name
      @gateway_name ||= Financial::GatewaySetting.find_by(account_id: @budget.account_id)&.gateway || 'manual'
    end
  end
end
