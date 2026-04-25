module Financial
  class ProcessRecurringExpensesJob < ApplicationJob
    queue_as :default

    def perform
      # Itera sobre todas as accounts que tenham despesas recorrentes ativas
      Account.find_each do |account|
        ::Financial::RecurringExpenseGenerator.call(account_id: account.id)
      end
    end
  end
end
