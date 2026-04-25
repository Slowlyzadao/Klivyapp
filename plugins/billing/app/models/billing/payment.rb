module Billing
  class Payment < ApplicationRecord
    self.table_name = 'billing_payments'

    belongs_to :subscription, class_name: 'Billing::Subscription'

    enum :status, { pending: 0, confirmed: 1, overdue: 2, canceled: 3 }

    validates :status, :amount, :due_date, presence: true
  end
end
