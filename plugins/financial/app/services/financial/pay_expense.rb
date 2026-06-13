module Financial
  # Paga uma despesa (Expense). Cadeia de efeitos atomica:
  #   1. Expense.status → pago, paid_amount_cents += amount, paid_at = received_at
  #   2. Cria Entry de saída na conta (Fluxo + DRE com categoria).
  #   3. Bloqueia se a conta destino é caixa físico e a sessão não está aberta.
  #
  # Suporta pagamento parcial: se amount_cents < remaining, status fica 'pendente' (parcial)
  # — a despesa só vira 'pago' quando paid_amount_cents >= amount_cents.
  class PayExpense
    Result = Financial::ServiceResult

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(expense:, actor:, bank_account:, amount_cents: nil, paid_at: nil,
                   payment_method: nil, payment_method_record: nil, notes: nil,
                   interest_cents: 0, interest_type: 'fixed', interest_value: 0,
                   fine_cents: 0,     fine_type: 'fixed',     fine_value: 0,
                   discount_cents: 0, discount_type: 'fixed', discount_value: 0)
      @expense = expense
      @actor = actor
      @bank_account = bank_account
      @amount_cents = amount_cents
      # Garante Date (controller passa String) — evita NoMethodError em
       # `.year`/`.strftime` quando algum callee recebe a ref crua.
      @paid_at = if paid_at.blank?
                   Date.current
                 elsif paid_at.is_a?(String)
                   Date.parse(paid_at)
                 else
                   paid_at.to_date
                 end
      @payment_method = payment_method || @expense.payment_method
      # Refactor 2026-05-24: PaymentMethod específico (Settings → Formas).
      # Quando vier, grava `payment_method_id` na Expense pra rastreabilidade.
      @payment_method_record = payment_method_record
      @notes = notes
      # Modificadores: cents = valor final aplicado; type+value = intenção
      # original do operador (preservada pra auditoria/relatórios).
      @interest_cents = interest_cents.to_i
      @interest_type  = interest_type
      @interest_value = interest_value.to_f
      @fine_cents = fine_cents.to_i
      @fine_type  = fine_type
      @fine_value = fine_value.to_f
      @discount_cents = discount_cents.to_i
      @discount_type  = discount_type
      @discount_value = discount_value.to_f
    end

    def call
      return Result.failure('despesa não pode ser paga (status atual)') unless payable?

      apply_amount = (@amount_cents || @expense.remaining_cents).to_i
      return Result.failure('amount_cents > 0 obrigatório') if apply_amount <= 0
      return Result.failure('amount_cents excede saldo') if apply_amount > @expense.remaining_cents

      # Caixa físico: bloqueia pagamento em dinheiro com data em sessão fechada.
      if @bank_account.cash?
        open_register = Financial::CashRegister.for_account(@expense.account_id)
                          .where(financial_bank_account_id: @bank_account.id, session_date: @paid_at, status: 'open')
                          .exists?
        return Result.failure("Caixa do dia #{@paid_at.strftime('%d/%m/%Y')} fechado.") unless open_register
      end

      entry = nil
      ActiveRecord::Base.transaction do
        @expense.lock!

        new_paid = @expense.paid_amount_cents + apply_amount
        new_status = new_paid >= @expense.amount_cents ? 'pago' : 'pendente'

        # Valor líquido efetivo a debitar = principal + juros + multa − desconto.
        # Esse é o valor que sai do caixa (cria Entry com esse total).
        # `paid_amount_cents` da Expense usa SÓ o principal (sem modificadores) —
        # rastreia "quanto do valor original foi quitado". Modificadores ficam
        # em colunas dedicadas pra auditoria + relatórios analíticos.
        effective_out_cents = apply_amount + @interest_cents + @fine_cents - @discount_cents

        @expense.update!(
          paid_amount_cents: new_paid,
          status: new_status,
          paid_at: new_status == 'pago' ? @paid_at : nil,
          paid_by_id: new_status == 'pago' ? @actor&.id : nil,
          payment_method: @payment_method,
          payment_method_id: @payment_method_record&.id,
          financial_bank_account_id: @bank_account.id,
          interest_amount_cents: @interest_cents,
          interest_type:  @interest_type,
          interest_value: @interest_value,
          fine_amount_cents: @fine_cents,
          fine_type:  @fine_type,
          fine_value: @fine_value,
          discount_amount_cents: @discount_cents,
          discount_type:  @discount_type,
          discount_value: @discount_value
        )

        entry = Financial::Entry.create!(
          account_id: @expense.account_id,
          financial_bank_account_id: @bank_account.id,
          financial_dre_category_id: @expense.financial_dre_category_id,
          direction: 'out',
          kind: 'despesa',
          amount_cents: effective_out_cents,
          payment_method: @payment_method,
          competence_date: @expense.competence_date,
          cash_date: @paid_at,
          description: @expense.description,
          source_type: 'Financial::Expense',
          source_id: @expense.id,
          affects_dre: true,
          affects_cashflow: true,
          cash_register_id: cash_register_id_if_cash,
          registered_by_id: @actor&.id
        )

        # Se a despesa é origem de uma comissão devida, marca a CommissionEntry como paga.
        if @expense.financial_commission_entry_id.present? && new_status == 'pago'
          Financial::CommissionEntry.where(id: @expense.financial_commission_entry_id)
                                    .update_all(status: 'paga', paid_at: @paid_at, paid_by_id: @actor&.id)
        end
      end

      Result.success(expense: @expense.reload, entry: entry)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    def payable?
      %w[pendente vencido].include?(@expense.status)
    end

    def cash_register_id_if_cash
      return nil unless @bank_account.cash?

      Financial::CashRegister
        .for_account(@expense.account_id)
        .where(financial_bank_account_id: @bank_account.id, session_date: @paid_at, status: 'open')
        .pick(:id)
    end
  end
end
