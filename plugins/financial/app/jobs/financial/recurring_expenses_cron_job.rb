module Financial
  # Cron diário às 00:01 — gera as despesas das próximas competências para todas as contas.
  # Canon §4.4 — "Roda às 00:01 todo dia".
  # Configurar em config/sidekiq_cron.yml ou whenever para invocar daily.
  class RecurringExpensesCronJob < ApplicationJob
    queue_as :scheduled

    def perform
      result = Financial::GenerateRecurringExpenses.run!
      Rails.logger.info(
        "[Financial::RecurringExpensesCronJob] generated=#{result[:generated]} " \
        "skipped=#{result[:skipped]} accounts=#{result[:accounts]}"
      )
    end
  end
end
