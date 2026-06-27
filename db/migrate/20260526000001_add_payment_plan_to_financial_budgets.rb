# Adiciona `payment_plan` JSONB em `financial_budgets` — snapshot da
# "intenção original" do wizard de configuração de pagamento (Fase F1
# da auditoria em docs/03-engineering/financeiro-fluxo-aprovacao-parcelamento.md).
#
# Diferente das parcelas vivas (Financial::Installment) que podem ser
# editadas via BUG-02 após aprovação, `payment_plan` preserva como a
# recepção configurou inicialmente — útil para auditoria visual e
# reconciliação ("o que mudou desde a aprovação?").
#
# Esquema do payload (controlled em app code, NÃO na coluna):
#   {
#     "version": "v2",
#     "wizard_session_id": "<uuid>",
#     "configured_at": "<iso8601 -03:00>",
#     "configured_by_id": <user_id>,
#     "discount": { "kind": "fixo|percentual", "value_cents": 5000 },
#     "installments_plan": [
#       {
#         "amount_cents": 50000,
#         "due_date": "2026-05-26",
#         "payment_method": "pix",
#         "payment_method_id": 1,
#         "professional_id": 42,
#         "expected_fee_cents": 0,
#         "expected_net_cents": 50000
#       }
#     ],
#     "totals": { ... }
#   }
#
# Default `{}` mantém retrocompat — budgets antigos ficam com plan vazio,
# wizard novo popula. Index GIN permite query "todos os budgets aprovados
# via wizard v2" e drill-down por keys do payload.
class AddPaymentPlanToFinancialBudgets < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_budgets, :payment_plan, :jsonb, default: {}, null: false
    add_index  :financial_budgets, :payment_plan, using: :gin, name: 'idx_financial_budgets_payment_plan_gin'
  end
end
