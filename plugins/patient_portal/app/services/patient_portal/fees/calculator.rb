# Cálculo puro de valor de fee (Sprint H).
#
# Separado em service próprio pra ser testável sem precisar mockar appointment,
# budget ou nada — recebe primitivos, retorna Integer (cents). Reusado por
# LateCancelFeeAssessor e NoShowFeeAssessor.
#
# Regra: prioridade explícita por valor absoluto sobre percentual. Se ambos
# vierem setados, o valor absoluto vence (clínica configurou os dois → quis
# fixar o valor).
module PatientPortal
  module Fees
    class Calculator
      # @param fixed_cents [Integer, nil] valor absoluto configurado pela clínica
      # @param percent     [Numeric, nil] % de 0..100 sobre `base_cents`
      # @param base_cents  [Integer]      base de cálculo (preço do serviço/sessão)
      # @return [Integer] fee em cents (>= 0)
      def self.compute(fixed_cents:, percent:, base_cents:)
        return fixed_cents.to_i if fixed_cents.to_i.positive?
        return 0 if percent.to_f <= 0 || base_cents.to_i <= 0

        ((base_cents.to_f * percent.to_f) / 100.0).round
      end
    end
  end
end
