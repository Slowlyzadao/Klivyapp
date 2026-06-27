module Financial
  # Cron diário — gera Budget+Installment de cada `RecurringBilling` ativo
  # cujo `next_generation_at <= today`. Espelha o `RecurringExpensesCronJob`
  # (despesas fixas) mas para o lado de receita.
  #
  # Roda às 02:30 UTC no schedule.yml — antes do `AutoSettleCardInstallmentsJob`
  # (03:30 UTC), garantindo que parcelas geradas hoje sejam captadas pelo job
  # de auto-baixa se for cartão com settlement_mode=on_due_date e o vencimento
  # também for hoje.
  #
  # Idempotência: o serviço avança `next_generation_at` ao gerar; mesmo
  # billing não cai duas vezes no mesmo dia. Falha em um billing não derruba
  # os outros — best-effort por billing, loga warn.
  class GenerateRecurringBillingsJob < ApplicationJob
    queue_as :scheduled

    def perform
      today = Time.zone.today
      counts = { generated: 0, failed: 0, accounts: 0 }

      Account.find_each do |account|
        result = process_account(account, today)
        counts[:generated] += result[:generated]
        counts[:failed]    += result[:failed]
        counts[:accounts]  += 1
      end

      Rails.logger.info(
        "[Financial::GenerateRecurringBillingsJob] " \
        "generated=#{counts[:generated]} failed=#{counts[:failed]} " \
        "accounts=#{counts[:accounts]}"
      )
      counts
    end

    private

    def process_account(account, today)
      counts = { generated: 0, failed: 0 }

      Financial::RecurringBilling
        .where(account_id: account.id, deleted_at: nil)
        .due_today(today)
        .find_each do |billing|
        attempt_generate(billing, today, counts)
      end

      counts
    end

    def attempt_generate(billing, today, counts)
      result = Financial::GenerateRecurringInstallments.call(
        recurring_billing: billing,
        today: today
      )

      if result.success?
        counts[:generated] += 1
      else
        counts[:failed] += 1
        Rails.logger.warn(
          "[Financial::GenerateRecurringBillingsJob] falha billing=#{billing.id} " \
          "account=#{billing.account_id}: #{result.errors.join('; ')}"
        )
      end
    end
  end
end
