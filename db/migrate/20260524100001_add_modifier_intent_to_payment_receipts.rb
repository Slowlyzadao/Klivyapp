# Persiste a INTENÇÃO original do operador ao registrar juros/multa/desconto,
# não só o valor final em centavos. Padrão de mercado (Conta Azul, Omie, Bling,
# Asaas) — permite distinguir "10% desconto" de "R$ 100 fixo" para:
#   - Recibo do cliente ("10% = R$ 50,00")
#   - Relatórios analíticos ("% médio de desconto por mês")
#   - Auditoria ("operador concedeu 10%, não R$ X aleatório")
#
# Compatibilidade total: as colunas `*_amount_cents` existentes continuam sendo
# a SOURCE OF TRUTH pro valor monetário aplicado. As novas colunas guardam só
# a INTENÇÃO (tipo + valor digitado original):
#   - `_type`  = 'fixed' | 'percent'
#   - `_value` = decimal digitado (R$ se fixed, % se percent)
#
# Default 'fixed' preserva semântica dos registros existentes (que vieram do
# fluxo antigo R$ apenas) — backfill desnecessário, intenção implícita é R$.
class AddModifierIntentToPaymentReceipts < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_payment_receipts, :interest_type,  :string,  limit: 16, null: false, default: 'fixed'
    add_column :financial_payment_receipts, :interest_value, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :financial_payment_receipts, :fine_type,      :string,  limit: 16, null: false, default: 'fixed'
    add_column :financial_payment_receipts, :fine_value,     :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :financial_payment_receipts, :discount_type,  :string,  limit: 16, null: false, default: 'fixed'
    add_column :financial_payment_receipts, :discount_value, :decimal, precision: 10, scale: 2, default: 0, null: false

    add_check_constraint :financial_payment_receipts,
                         "interest_type IN ('fixed','percent')",
                         name: 'chk_receipt_interest_type'
    add_check_constraint :financial_payment_receipts,
                         "fine_type IN ('fixed','percent')",
                         name: 'chk_receipt_fine_type'
    add_check_constraint :financial_payment_receipts,
                         "discount_type IN ('fixed','percent')",
                         name: 'chk_receipt_discount_type'

    # Validação de range:
    # - tipo fixed: valor em R$, sem limite superior (poderia ser milhares)
    # - tipo percent: valor em %, [0..99.99] (proibe 100% que zeraria recebimento)
    # Check constraint compara com o tipo via CASE pra cobrir ambos sem ser
    # restritivo demais no caso fixed.
    add_check_constraint :financial_payment_receipts,
                         "interest_value >= 0 AND (interest_type <> 'percent' OR interest_value < 100)",
                         name: 'chk_receipt_interest_value_range'
    add_check_constraint :financial_payment_receipts,
                         "fine_value >= 0 AND (fine_type <> 'percent' OR fine_value < 100)",
                         name: 'chk_receipt_fine_value_range'
    add_check_constraint :financial_payment_receipts,
                         "discount_value >= 0 AND (discount_type <> 'percent' OR discount_value < 100)",
                         name: 'chk_receipt_discount_value_range'
  end
end
