module Asaas
  class HandleWebhook
    def initialize(payload)
      @payload = payload
      @event = payload['event']
      @payment_data = payload['payment'] || {}
    end

    def perform
      return false unless @payment_data.present? && @event.present?

      subscription = find_subscription
      # Without a subscription matched, we drop the webhook processing as we can't tie it to an Account
      return false unless subscription

      case @event
      when 'PAYMENT_RECEIVED', 'PAYMENT_CONFIRMED'
        handle_payment_success(subscription)
      when 'PAYMENT_OVERDUE'
        handle_payment_overdue(subscription)
      when 'SUBSCRIPTION_CANCELED', 'PAYMENT_DELETED'
        handle_subscription_canceled(subscription)
      end

      true
    end

    private

    def find_subscription
      # Priority 1: Match by the Asaas subscription ID directly
      sub_id = @payment_data['subscription']
      return Billing::Subscription.find_by(asaas_subscription_id: sub_id) if sub_id.present?

      # Priority 2: Fallback to the account_id which was pushed to externalReference in Asaas
      external_ref = @payment_data['externalReference']
      return Billing::Subscription.find_by(account_id: external_ref) if external_ref.present?

      nil
    end

    STATUS_PRIORITY = {
      'PENDING' => 1,
      'RECEIVED' => 2,
      'CONFIRMED' => 3,
      'OVERDUE' => 4
    }.freeze

    def handle_payment_success(subscription)
      process_payment_update(subscription, :confirmed, :active)
    end

    def handle_payment_overdue(subscription)
      process_payment_update(subscription, :overdue, :overdue)
    end

    def process_payment_update(subscription, target_payment_status, target_subscription_status)
      payment = Billing::Payment.find_or_initialize_by(
        asaas_payment_id: @payment_data['id'] || 'no_payment_id'
      )
      payment.subscription = subscription

      incoming_status = @payment_data['status']

      # Convert current DB enum string to match Priority Map conceptual level
      # Default to 0 so new records or unmapped ones don't break
      current_level = case payment.status
                      when 'pending' then 1
                      when 'confirmed' then 3
                      when 'overdue' then 4
                      else 0
                      end

      ActiveRecord::Base.transaction do
        if payment.new_record? || (STATUS_PRIORITY[incoming_status] || 0) >= current_level
          payment.status = target_payment_status
        end

        payment.assign_attributes(
          amount: @payment_data['value'],
          due_date: @payment_data['dueDate'],
          paid_at: @payment_data['paymentDate'] || @payment_data['clientPaymentDate'] || Time.current
        )
        payment.save!
        
        subscription.update!(
          status: target_subscription_status, 
          next_due_date: @payment_data['dueDate']
        )
      end
    end

    def handle_subscription_canceled(subscription)
      # This triggers suspend callbacks
      subscription.update!(status: :canceled)
    end
  end
end
