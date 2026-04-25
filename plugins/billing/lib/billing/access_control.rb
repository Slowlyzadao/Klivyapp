module Billing
  module AccessControl
    extend ActiveSupport::Concern

    included do
      before_action :check_billing_status
    end

    private

    def check_billing_status
      # Do not check billing status during Devise authentication flows
      return if devise_controller?

      # Only block authenticated routes 
      return if current_user.blank? 
      return if current_user.try(:super_admin?) || current_user.class.name == 'SuperAdmin'
      return if Current.account.blank?
      
      # Whitelist - Never block the following routes
      if request.path.start_with?('/api/v1/billing/onboarding') || 
         request.path.start_with?('/api/v1/billing/webhooks') ||
         request.path.start_with?('/api/v1/billing/subscription') ||
         request.path.start_with?('/auth')
        return
      end

      subscription = Current.account.billing_subscription
      
      if subscription.present?
        # Only Active or Trial accounts have access to the system internally
        unless %w[active trial lead].include?(subscription.status)
          if request.format.json?
            render json: { error: "payment_required", status: subscription.status }, status: 402
          else
            head :payment_required
          end
        end
      end
    end
  end
end
