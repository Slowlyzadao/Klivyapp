# Adiciona `passes_fee_to_patient` em `financial_payment_methods` — modelo de
# repasse de MDR ao paciente (F2.5 do PaymentPlanWizardV2).
#
# Quando `true` para um método, o `Financial::ApproveBudget` infla o valor de
# cada parcela vinculada por: amount = (base + fixed) / (1 - bps/10000),
# de modo que a clínica receba o valor base cheio depois da operadora
# reter o MDR.
#
# Exemplo: parcela base R$ 200, fee 3,5% + R$ 0,39:
#   amount = (200 + 0,39) / (1 - 0,035) ≈ R$ 207,66 (paciente paga)
#   fee retida ≈ R$ 7,66
#   clínica recebe R$ 200,00 (= base)
#
# Default `false` mantém retrocompat — comportamento atual do V2 (clínica
# absorve a taxa) continua valendo para todas as PaymentMethods existentes.
# Operador ativa o repasse caso a caso via Settings → Formas de Pagamento.
#
# Conceitualmente: PIX/Dinheiro/Boleto normalmente ficam false (sem MDR);
# Crédito/Débito normalmente ficam true em clínicas que repassam taxa.
# Decisão fica com a clínica, não imposta por seed.
class AddPassesFeeToPatientToFinancialPaymentMethods < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_payment_methods, :passes_fee_to_patient, :boolean,
               default: false, null: false
  end
end
