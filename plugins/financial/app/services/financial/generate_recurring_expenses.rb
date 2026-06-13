module Financial
  # Gera Expenses futuras (próximos N dias) a partir de cada RecurringExpense ativa.
  # Idempotente: verifica se já existe Expense para a competência via
  # (financial_recurring_expense_id, competence_date) → não duplica.
  # Canon §4.4 + F-22.
  #
  # Uso:
  #   Financial::GenerateRecurringExpenses.run!  # para todas as contas
  #   Financial::GenerateRecurringExpenses.for_account(account)
  class GenerateRecurringExpenses
    HORIZON_DAYS = Financial::RecurringExpense::GENERATION_HORIZON_DAYS

    # Auditoria 2026-05-22 (`ALTO-SVC-02`): default era `Date.current` que em
    # containers UTC sem TZ definida pode gerar despesa pro dia errado quando
    # o app está configurado pra `America/Sao_Paulo` (BRT-3). `Time.zone.today`
    # respeita `Rails.application.config.time_zone` consistentemente.
    def self.run!(today: Time.zone.today)
      counts = { generated: 0, skipped: 0, accounts: 0 }
      Account.find_each do |account|
        result = for_account(account, today: today)
        counts[:generated] += result[:generated]
        counts[:skipped]   += result[:skipped]
        counts[:accounts]  += 1
      end
      counts
    end

    def self.for_account(account, today: Time.zone.today)
      generated = 0
      skipped = 0

      Financial::RecurringExpense
        .for_account(account.id)
        .active_recurring
        .find_each do |rec|
          target_dates = next_dates_until_horizon(rec, today)
          target_dates.each do |due_date|
            # `account_id` é redundante (financial_recurring_expense_id é PK
            # global única e `rec` já vem scoped por conta), mas explicitar
            # mantém defesa em profundidade caso o esquema mude no futuro.
            existed = Financial::Expense.unscoped.exists?(
              account_id: rec.account_id,
              financial_recurring_expense_id: rec.id,
              due_date: due_date
            )
            if existed
              skipped += 1
              next
            end

            create_expense_from_template(rec, due_date)
            generated += 1
          end
        end

      { generated: generated, skipped: skipped }
    end

    def self.next_dates_until_horizon(rec, today)
      end_at = today + HORIZON_DAYS
      list = []
      cursor = rec.next_due_date(today)
      while cursor && cursor <= end_at
        list << cursor
        next_one = rec.next_due_date(cursor + 1)
        break if next_one.nil? || next_one == cursor

        cursor = next_one
      end
      list
    end

    def self.create_expense_from_template(rec, due_date)
      Financial::Expense.create!(
        account_id: rec.account_id,
        financial_dre_category_id: rec.financial_dre_category_id,
        financial_bank_account_id: rec.financial_bank_account_id,
        financial_recurring_expense_id: rec.id,
        description: rec.name,
        amount_cents: rec.amount_cents,
        status: 'pendente',
        competence_date: rec.competence_for(due_date),
        due_date: due_date,
        installments_count: 1,
        installment_number: 1
      )
    end
  end
end
