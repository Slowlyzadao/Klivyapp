module Billing
  class Subscription < ApplicationRecord
    self.table_name = 'billing_subscriptions'
    
    # Adicionado :lead para contemplar Planos Enterprise de Venda Indireta
    enum :status, { trial: 0, pending: 1, active: 2, overdue: 3, canceled: 4, lead: 5 }

    belongs_to :account
    has_many :payments, class_name: 'Billing::Payment', dependent: :destroy

    validates :status, presence: true
    validates :plan, presence: true, on: :update

    after_save :sync_account_status, if: :saved_change_to_status?

    def activate_account!
      return if account.active?
      account.update!(status: :active)
    end

    def suspend_account!
      return if account.suspended?
      account.update!(status: :suspended)
    end

    private

    def sync_account_status
      case status.to_sym
      when :active
        activate_account!
      when :overdue, :canceled
        suspend_account!
      end
    end
  end
end
