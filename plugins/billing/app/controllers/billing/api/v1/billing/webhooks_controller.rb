module Billing
module Api
  module V1
    module Billing
      class WebhooksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :check_billing_status, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        def asaas
          # Dispatch immediately to background job to prevent Asaas timeouts
          # passing parameters as a clean hash
          ::Billing::ProcessAsaasWebhookJob.perform_later(params.except(:action, :controller).to_unsafe_h)

          # Always return 200 immediately
          render json: { success: true }, status: :ok
        end
      end
    end
  end
end
end
