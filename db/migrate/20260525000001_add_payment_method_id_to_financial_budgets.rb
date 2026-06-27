# Adiciona `payment_method_id` em `financial_budgets` — referência ao
# PaymentMethod específico configurado em Settings (canon §3).
#
# Quando setado, o `Financial::ApproveBudget` propaga esse id pra cada
# Installment gerada (a menos que o plano custom defina método próprio
# por parcela). Permite rastreabilidade: "qual provedor foi sugerido no
# orçamento?" + estatística "% de orçamentos com Cielo vs Stone".
#
# Mantém `payment_method` (string kind) por compat — código legado que
# lê só o kind continua funcionando. Quando `payment_method_id` vem, o
# kind é derivado automaticamente do PaymentMethod referenciado.
#
# FK on_delete: :restrict — não permite deletar PaymentMethod que tem
# Budget vinculado (preserva rastreabilidade).
class AddPaymentMethodIdToFinancialBudgets < ActiveRecord::Migration[7.1]
  def change
    add_column      :financial_budgets, :payment_method_id, :bigint
    add_index       :financial_budgets, :payment_method_id
    add_foreign_key :financial_budgets, :financial_payment_methods,
                    column: :payment_method_id, on_delete: :restrict
  end
end
