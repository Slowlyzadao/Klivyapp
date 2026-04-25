module CustomExceptions
  module Billing
    class AsaasError < StandardError; end
    class PaymentRequired < StandardError; end
  end
end
