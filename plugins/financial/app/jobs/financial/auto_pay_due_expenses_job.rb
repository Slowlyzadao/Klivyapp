module Financial
  # Cron diário — paga automaticamente as Expenses vencendo hoje (ou já
  # vencidas e ainda pendentes) cuja RecurringExpense de origem tem
  # `auto_pay=true`. Canon §4.4 (despesa fixa em débito automático).
  #
  # Comportamento:
  #   1. Acha Expense.status in [pendente, vencido] com due_date <= hoje
  #      vinda de RecurringExpense.auto_pay=true
  #   2. Determina conta bancária (da Expense; fallback pra da RecurringExpense)
  #   3. Valida saldo suficiente
  #   4. Chama PayExpense.call(...) com actor=nil (sistema)
  #   5. Sucesso: deixa pago, limpa flags de erro
  #   6. Falha: deixa pendente, grava motivo em `metadata.auto_pay_error`
  #      pra UI mostrar como warning na lista A Pagar
  #
  # Idempotência: não tenta de novo no mesmo dia se já tentou e falhou
  # (`metadata.auto_pay_attempted_at == hoje`). Isso evita spam de logs
  # quando o saldo fica insuficiente N dias seguidos.
  #
  # Roda DEPOIS do RecurringExpensesCronJob (que gera as Expenses) — daí
  # o offset de 1h no schedule.yml (gera 02:00, paga 03:00).
  class AutoPayDueExpensesJob < ApplicationJob
    queue_as :scheduled

    def perform
      today = Time.zone.today
      counts = { paid: 0, failed: 0, skipped: 0, accounts: 0 }

      Account.find_each do |account|
        result = process_account(account, today)
        counts[:paid]    += result[:paid]
        counts[:failed]  += result[:failed]
        counts[:skipped] += result[:skipped]
        counts[:accounts] += 1
      end

      Rails.logger.info(
        "[Financial::AutoPayDueExpensesJob] " \
        "paid=#{counts[:paid]} failed=#{counts[:failed]} " \
        "skipped=#{counts[:skipped]} accounts=#{counts[:accounts]}"
      )
      counts
    end

    private

    def process_account(account, today)
      counts = { paid: 0, failed: 0, skipped: 0 }

      candidates(account, today).find_each do |expense|
        # Backoff: se já tentou hoje e falhou, não tenta de novo no
        # mesmo dia — o operador precisa resolver (corrigir saldo,
        # mudar conta, etc) pra próxima rodada.
        last_attempt = expense.metadata&.dig('auto_pay_attempted_at')
        if last_attempt && safe_parse_date(last_attempt) == today
          counts[:skipped] += 1
          next
        end

        attempt_pay(expense, today, counts)
      end

      counts
    end

    def candidates(account, today)
      Financial::Expense
        .for_account(account.id)
        .alive
        .where(status: %w[pendente vencido])
        .where('financial_expenses.due_date <= ?', today)
        .joins(
          'INNER JOIN financial_recurring_expenses rec ' \
          'ON rec.id = financial_expenses.financial_recurring_expense_id'
        )
        .where('rec.auto_pay = ? AND rec.deleted_at IS NULL', true)
    end

    def attempt_pay(expense, today, counts)
      bank = bank_account_for(expense)

      unless bank
        record_failure(expense, today,
                       'Sem conta bancária configurada — defina em Despesas Fixas')
        counts[:failed] += 1
        return
      end

      if bank.current_balance_cents.to_i < expense.amount_cents.to_i
        record_failure(expense, today,
                       "Saldo insuficiente em #{bank.name} " \
                       "(disponível #{format_brl(bank.current_balance_cents)})")
        counts[:failed] += 1
        return
      end

      result = Financial::PayExpense.call(
        expense: expense,
        actor: nil, # nil = sistema (auto-pay) — appears as registered_by_id=nil
        bank_account: bank,
        paid_at: today,
        notes: 'Pagamento automático (auto_pay)'
      )

      if result.success?
        clear_failure(expense)
        counts[:paid] += 1
      else
        record_failure(expense, today, result.errors.join('; '))
        counts[:failed] += 1
      end
    end

    def bank_account_for(expense)
      scope = Financial::BankAccount.for_account(expense.account_id).alive.where(active: true)
      scope.find_by(id: expense.financial_bank_account_id) ||
        scope.find_by(id: expense.financial_recurring_expense&.financial_bank_account_id)
    end

    def record_failure(expense, today, reason)
      meta = (expense.metadata || {}).merge(
        'auto_pay_error' => reason,
        'auto_pay_attempted_at' => today.iso8601
      )
      expense.update_columns(metadata: meta, updated_at: Time.current)
      Rails.logger.warn(
        "[Financial::AutoPayDueExpensesJob] expense=#{expense.id} " \
        "account=#{expense.account_id} reason=#{reason}"
      )
    end

    def clear_failure(expense)
      return unless expense.metadata.is_a?(Hash) && expense.metadata.key?('auto_pay_error')

      cleaned = expense.metadata.except('auto_pay_error', 'auto_pay_attempted_at')
      expense.update_columns(metadata: cleaned, updated_at: Time.current)
    end

    def format_brl(cents)
      "R$ #{(cents.to_i / 100.0).round(2).to_s.gsub('.', ',')}"
    end

    def safe_parse_date(str)
      Date.parse(str.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
