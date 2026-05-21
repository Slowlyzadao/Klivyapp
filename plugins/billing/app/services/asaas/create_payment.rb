module Asaas
  # Cria uma cobrança avulsa (não-recorrente) no Asaas via POST /payments.
  # Usada para os descontos de cupons do tipo :percent — cada mês de desconto
  # vira uma cobrança avulsa com valor reduzido.
  #
  # O cartão é referenciado via `credit_card_token`, obtido quando a
  # subscription principal do cliente foi criada.
  class CreatePayment
    def initialize(customer_id:, value:, due_date:, description:, credit_card_token:,
                   customer_ip: nil, external_reference: nil)
      @customer_id = customer_id
      @value = value
      @due_date = due_date
      @description = description
      @credit_card_token = credit_card_token
      @customer_ip = customer_ip
      @external_reference = external_reference
    end

    def perform
      payload = {
        customer: @customer_id,
        billingType: 'CREDIT_CARD',
        value: @value,
        dueDate: @due_date.strftime('%Y-%m-%d'),
        description: @description,
        creditCardToken: @credit_card_token
      }
      payload[:remoteIp] = @customer_ip if @customer_ip.present?
      payload[:externalReference] = @external_reference.to_s if @external_reference.present?

      client = Asaas::ApiClient.new
      response = client.post('payments', payload)

      {
        asaas_payment_id: response['id'],
        status: response['status'],
        value: response['value'],
        due_date: response['dueDate']
      }
    end
  end
end
