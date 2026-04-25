module Billing
module Api
  module V1
    module Billing
      class SubscriptionController < ApplicationController
        skip_before_action :verify_authenticity_token, raise: false
        before_action :authenticate_user!

        def show
          account_id = request.headers['account_id'] || params[:account_id]
          account = current_user.accounts.find(account_id)
          
          subscription = account.billing_subscription

          render json: {
            status: subscription.status,
            plan: subscription.plan,
            price: subscription.price,
            coupon_code: subscription.coupon_code,
            coupon_expires_at: subscription.coupon_expires_at,
            asaas_subscription_id: subscription.asaas_subscription_id.present?
          }
        end
      end
    end
  end
end
end
