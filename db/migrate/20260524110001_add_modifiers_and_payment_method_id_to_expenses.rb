# Despesa ganha simetria com Receber Pagamento:
#   1. `payment_method_id` (FK pra financial_payment_methods) — permite usar
#      o método específico configurado em Settings ("PIX Cielo", "Crédito Stone")
#      em vez de só o kind canon string. Mantém `payment_method` (string) pra
#      compat e relatórios legacy.
#   2. `interest/fine/discount` (cents + type + value) — antes eram exibidos no
#      modal mas o backend ignorava silenciosamente. Agora persistidos com
#      intenção original (tipo+value) + cents finais aplicados, mesmo padrão
#      do PaymentReceipt (canon de mercado).
#
# Default 'fixed' + 0 preserva semântica dos registros existentes (não houve
# uso de modificadores antes — backfill desnecessário).
class AddModifiersAndPaymentMethodIdToExpenses < ActiveRecord::Migration[7.1]
  def change
    # FK opcional pro PaymentMethod específico — kind canon continua em
    # `payment_method` (string) por compat. Quando vier o _id, é a fonte
    # primária; sem ele, fallback pro string.
    add_column      :financial_expenses, :payment_method_id, :bigint
    add_index       :financial_expenses, :payment_method_id
    add_foreign_key :financial_expenses, :financial_payment_methods,
                    column: :payment_method_id, on_delete: :restrict

    # Modificadores — mesma estrutura do payment_receipts.
    add_column :financial_expenses, :interest_amount_cents, :bigint,  null: false, default: 0
    add_column :financial_expenses, :interest_type,         :string,  limit: 16, null: false, default: 'fixed'
    add_column :financial_expenses, :interest_value,        :decimal, precision: 10, scale: 2, null: false, default: 0
    add_column :financial_expenses, :fine_amount_cents,     :bigint,  null: false, default: 0
    add_column :financial_expenses, :fine_type,             :string,  limit: 16, null: false, default: 'fixed'
    add_column :financial_expenses, :fine_value,            :decimal, precision: 10, scale: 2, null: false, default: 0
    add_column :financial_expenses, :discount_amount_cents, :bigint,  null: false, default: 0
    add_column :financial_expenses, :discount_type,         :string,  limit: 16, null: false, default: 'fixed'
    add_column :financial_expenses, :discount_value,        :decimal, precision: 10, scale: 2, null: false, default: 0

    add_check_constraint :financial_expenses,
                         "interest_type IN ('fixed','percent')",
                         name: 'chk_expense_interest_type'
    add_check_constraint :financial_expenses,
                         "fine_type IN ('fixed','percent')",
                         name: 'chk_expense_fine_type'
    add_check_constraint :financial_expenses,
                         "discount_type IN ('fixed','percent')",
                         name: 'chk_expense_discount_type'
    add_check_constraint :financial_expenses,
                         'interest_amount_cents >= 0',
                         name: 'chk_expense_interest_cents_nn'
    add_check_constraint :financial_expenses,
                         'fine_amount_cents >= 0',
                         name: 'chk_expense_fine_cents_nn'
    add_check_constraint :financial_expenses,
                         'discount_amount_cents >= 0',
                         name: 'chk_expense_discount_cents_nn'
    add_check_constraint :financial_expenses,
                         "interest_value >= 0 AND (interest_type <> 'percent' OR interest_value < 100)",
                         name: 'chk_expense_interest_value_range'
    add_check_constraint :financial_expenses,
                         "fine_value >= 0 AND (fine_type <> 'percent' OR fine_value < 100)",
                         name: 'chk_expense_fine_value_range'
    add_check_constraint :financial_expenses,
                         "discount_value >= 0 AND (discount_type <> 'percent' OR discount_value < 100)",
                         name: 'chk_expense_discount_value_range'
  end
end
