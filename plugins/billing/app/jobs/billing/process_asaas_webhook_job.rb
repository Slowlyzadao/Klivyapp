module Billing
  class ProcessAsaasWebhookJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Asaas::HandleWebhook.new(payload).perform
    end
  end
end
