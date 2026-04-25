module Billing
  module CouponRegistry
    # Fonte de verdade dos cupons no backend.
    # Toda mudança aqui precisa ser refletida em public/checkout.html e vice-versa.
    COUPONS = {
      # Trial (período grátis)
      'BEMVINDO'     => { kind: :trial, days: 3,   description: '3 dias grátis' },
      '0ZN6VBZZ'     => { kind: :trial, days: 7,   description: '7 dias grátis' },
      '1ZYTR06O'     => { kind: :trial, days: 14,  description: '14 dias grátis' },
      'AFLHM4QV'     => { kind: :trial, days: 30,  description: '1 mês grátis' },
      'HQJO6H8B'     => { kind: :trial, days: 60,  description: '2 meses grátis' },
      '7DAL4IXU'     => { kind: :trial, days: 90,  description: '3 meses grátis' },

      # 50% OFF
      'HPIG310M'     => { kind: :percent, percent: 50, months: 1,  description: '50% OFF por 1 mês' },
      'EQBMR6L0'     => { kind: :percent, percent: 50, months: 3,  description: '50% OFF por 3 meses' },
      'SN3UKRFO'     => { kind: :percent, percent: 50, months: 6,  description: '50% OFF por 6 meses' },
      'CSSRT526'     => { kind: :percent, percent: 50, months: 12, description: '50% OFF por 12 meses' },

      # 20% OFF
      'P5NW42NT'     => { kind: :percent, percent: 20, months: 1,  description: '20% OFF por 1 mês' },
      'OALAHIZ3'     => { kind: :percent, percent: 20, months: 3,  description: '20% OFF por 3 meses' },
      '9GZB25XN'     => { kind: :percent, percent: 20, months: 6,  description: '20% OFF por 6 meses' },
      'JOYSXQC4'     => { kind: :percent, percent: 20, months: 12, description: '20% OFF por 12 meses' },

      # 10% OFF
      'JD3Q5BSM'     => { kind: :percent, percent: 10, months: 1,  description: '10% OFF no primeiro mês' },
      'K2NXQS2M'     => { kind: :percent, percent: 10, months: 3,  description: '10% OFF por 3 meses' },
      '6LLN8U5A'     => { kind: :percent, percent: 10, months: 6,  description: '10% OFF por 6 meses' },
      'LPJ6ADUZ'     => { kind: :percent, percent: 10, months: 12, description: '10% OFF por 12 meses' },

      # Admin
      'RZGMTO6FSNQC' => { kind: :free_forever, description: 'Grátis para sempre' }
    }.freeze

    module_function

    def lookup(code)
      return nil if code.blank?
      COUPONS[code.to_s.strip.upcase]
    end

    def valid?(code)
      !lookup(code).nil?
    end

    # Transforma o cupom em um "plano de ações" a executar contra o Asaas.
    # Retorna:
    # {
    #   coupon_code:        string ou nil
    #   free_forever:       bool  (se true, NÃO cria subscription no Asaas)
    #   subscription_start: Date  (nextDueDate da assinatura recorrente)
    #   avulsa_charges:     Array de { value:, due_date:, description: }
    # }
    def plan_for(code, base_price)
      coupon = lookup(code)
      plan = {
        coupon_code: nil,
        free_forever: false,
        subscription_start: Date.current,
        avulsa_charges: []
      }
      return plan unless coupon

      plan[:coupon_code] = code.to_s.strip.upcase

      case coupon[:kind]
      when :trial
        plan[:subscription_start] = Date.current + coupon[:days].to_i.days

      when :percent
        months = coupon[:months].to_i
        percent = coupon[:percent].to_f
        discounted = (base_price.to_f * (1 - percent / 100.0)).round(2)

        plan[:subscription_start] = Date.current + months.months

        months.times do |i|
          plan[:avulsa_charges] << {
            value: discounted,
            due_date: Date.current + i.months,
            description: "Mensalidade #{i + 1}/#{months} com #{percent.to_i}% OFF (cupom #{plan[:coupon_code]})"
          }
        end

      when :free_forever
        plan[:free_forever] = true
      end

      plan
    end
  end
end
