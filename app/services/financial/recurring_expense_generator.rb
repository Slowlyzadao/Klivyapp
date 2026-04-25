module Financial
  class RecurringExpenseGenerator
    def self.call(account_id: nil)
      scope = RecurringExpense.pending_generation
      scope = scope.where(account_id: account_id) if account_id

      scope.find_each do |expense|
        new(expense).generate
      end
    end

    def initialize(expense)
      @expense = expense
    end

    def generate
      return unless should_generate?

      ActiveRecord::Base.transaction do
        # Primeira geração: usa start_date como referência para pegar o mês correto.
        # Gerações subsequentes: usa o mês seguinte ao last_generated_at.
        reference_date = if @expense.last_generated_at.nil?
                           @expense.start_date
                         else
                           @expense.last_generated_at.to_date.next_month
                         end

        max_day = Date.new(reference_date.year, reference_date.month, -1).day
        candidate_due_date = Date.new(reference_date.year, reference_date.month, [@expense.due_day, max_day].min)
        competence_date = @expense.next_competence_date(candidate_due_date)

        AccountTransaction.create!(
          account_id: @expense.account_id,
          recurring_expense_id: @expense.id,
          financial_category_id: @expense.financial_category_id,
          bank_account_id: @expense.bank_account_id,
          registered_by_id: @expense.registered_by_id,
          entry_type: 'saida',
          status: @expense.auto_confirm ? 'pago' : 'pendente',
          origin: 'recorrente',
          amount: @expense.amount,
          payment_method: @expense.payment_method,
          description: @expense.description,
          due_date: candidate_due_date,
          paid_at: @expense.auto_confirm ? candidate_due_date : nil,
          competence_date: competence_date,
          notes: @expense.notes
        )

        @expense.update!(last_generated_at: Time.current)
      end
    rescue StandardError => e
      Rails.logger.error("[Financial::RecurringExpenseGenerator] Falhou ao gerar a despesa recorrente #{@expense.id}: #{e.message}")
    end

    private

    def should_generate?
      return false unless @expense.active?

      # Nao gera se a data de inicio for no futuro
      return false if @expense.start_date.present? && @expense.start_date > Date.today

      # Nao gera se passou a data de fim
      return false if @expense.end_date.present? && @expense.end_date < Date.today

      true
    end
  end
end
