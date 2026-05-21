module Financial
  # Resolução do gateway de pagamento por conta.
  # Cada Account tem 0 ou 1 Financial::GatewaySetting; quando ausente, usa Manual.
  #
  # Uso típico:
  #   adapter = Financial::Gateways.adapter_for(account)
  #   result  = adapter.create_charge(installment: installment, customer: customer)
  module Gateways
    REGISTRY = {
      'manual' => 'Financial::Gateways::Manual',
      'asaas'  => 'Financial::Gateways::Asaas'
    }.freeze

    module_function

    def adapter_for(account)
      setting = Financial::GatewaySetting.find_by(account_id: account.id)
      gateway_name = setting&.gateway || 'manual'
      adapter_class = REGISTRY[gateway_name]&.safe_constantize
      raise UnknownGatewayError, "gateway #{gateway_name.inspect} not registered" unless adapter_class

      adapter_class.new(account: account, setting: setting)
    end

    def adapter_by_name(name, account:, setting: nil)
      klass = REGISTRY[name.to_s]&.safe_constantize
      raise UnknownGatewayError, "gateway #{name.inspect} not registered" unless klass

      klass.new(account: account, setting: setting)
    end

    class UnknownGatewayError < StandardError; end
    class GatewayError < StandardError
      attr_reader :code, :payload

      def initialize(message, code: nil, payload: nil)
        super(message)
        @code = code
        @payload = payload
      end
    end

    class NotImplementedError < GatewayError; end
  end
end
