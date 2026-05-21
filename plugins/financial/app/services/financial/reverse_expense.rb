module Financial
  # Estorna pagamento de despesa (CT-AP-08).
  # Cria Entry reversa de entrada (estorno_despesa), zera paid_amount_cents,
  # status volta para 'pendente'.
  class ReverseExpense
    Result = Financial::ServiceResult

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(expense:, actor:, reason: nil, reversed_at: nil)
      @expense = expense
      @actor = actor
      @reason = reason
      @reversed_at = reversed_at || Date.current
    end

    def call
      return Result.failure('despesa não está paga') unless @expense.status == 'pago'

      reversal = nil
      ActiveRecord::Base.transaction do
        @expense.lock!

        last_entry = Financial::Entry.where(
          source_type: 'Financial::Expense',
          source_id: @expense.id,
          direction: 'out',
          kind: 'despesa'
        ).order(created_at: :desc).first

        reversal = Financial::Entry.create!(
          account_id: @expense.account_id,
          financial_bank_account_id: @expense.financial_bank_account_id,
          financial_dre_category_id: @expense.financial_dre_category_id,
          direction: 'in',
          kind: 'estorno_despesa',
          amount_cents: @expense.paid_amount_cents,
          competence_date: @reversed_at,
          cash_date: @reversed_at,
          description: "Estorno: #{@expense.description}#{@reason ? " - #{@reason}" : ''}",
          source_type: 'Financial::Expense',
          source_id: @expense.id,
          reverses_entry_id: last_entry&.id,
          affects_dre: true,
          affects_cashflow: true,
          registered_by_id: @actor&.id
        )

        @expense.update!(
          status: 'estornado',
          paid_amount_cents: 0,
          paid_at: nil,
          paid_by_id: nil
        )
      end

      Result.success(expense: @expense.reload, reversal_entry: reversal)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end
  end
end
