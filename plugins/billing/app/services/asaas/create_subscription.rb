module Asaas
  class CreateSubscription
    PLAN_PRICING = {
      'standard' => 197.00,
      'premium' => 369.90
    }.freeze

    # `start_date` permite atrasar o primeiro vencimento (usado por cupons).
    # `coupon_code` vai apenas pra descrição/auditoria — NÃO altera o value.
    def initialize(customer_id, plan, credit_card_params, customer_ip, external_reference,
                   coupon_code: nil, start_date: nil)
      @customer_id = customer_id
      @plan = plan
      @credit_card_params = credit_card_params
      @customer_ip = customer_ip
      @external_reference = external_reference
      @coupon_code = coupon_code&.to_s&.strip&.upcase&.presence
      @start_date = start_date || Date.current
    end

    def perform
      price = PLAN_PRICING[@plan]
      raise ArgumentError, "Invalid plan" unless price

      payload = {
        customer: @customer_id,
        billingType: 'CREDIT_CARD',
        value: price,
        nextDueDate: @start_date.strftime('%Y-%m-%d'),
        cycle: 'MONTHLY',
        description: description_text,
        creditCard: @credit_card_params[:creditCard],
        creditCardHolderInfo: @credit_card_params[:creditCardHolderInfo],
        remoteIp: @customer_ip,
        externalReference: @external_reference.to_s
      }

      client = Asaas::ApiClient.new
      response = client.post('subscriptions', payload)

      {
        asaas_subscription_id: response['id'],
        status: response['status'],
        price: price,
        start_date: @start_date,
        credit_card_token: extract_credit_card_token(response)
      }
    end

    private

    def description_text
      base = "Assinatura Plano #{@plan.capitalize}"
      return base unless @coupon_code

      coupon = ::Billing::CouponRegistry.lookup(@coupon_code)
      return base unless coupon

      "#{base} (Cupom #{@coupon_code} - #{coupon[:description]})"
    end

    # O Asaas retorna o token do cartão na resposta quando a subscription é
    # criada com creditCard. Usamos esse token para cobranças avulsas
    # futuras (evita pedir o cartão de novo).
    def extract_credit_card_token(response)
      response.dig('creditCard', 'creditCardToken')
    end
  end
end
