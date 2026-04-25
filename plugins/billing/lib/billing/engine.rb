module Billing
  class Engine < ::Rails::Engine
    isolate_namespace Billing

    config.to_prepare do
      # Load middleware
      require_relative 'access_control'
      
      ApplicationController.class_eval do
        include Billing::AccessControl
      end

      Account.class_eval do
        has_one :billing_subscription, class_name: 'Billing::Subscription', dependent: :destroy

        def billing_subscription
          super || build_billing_subscription(status: :trial)
        end
      end
    end
  end
end
