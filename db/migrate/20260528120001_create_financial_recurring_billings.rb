# Mensalidade fixa de paciente — modelo de contrato recorrente que gera
# Budget+Installment a cada período. Decisão 2026-05-28: separar do Budget
# "Mensalidade" do modal Novo Lançamento (que era só uma label e gerava N
# parcelas upfront, não cumpria o que prometia).
#
# Casos de uso: ortodontia indeterminada, clube de assinatura, pacote mensal
# de consultas. Operador configura o contrato 1 vez; job diário gera as
# cobranças no `next_generation_at`.
#
# Geração espelha `Financial::RecurringExpense` (despesa fixa) — mesma máquina,
# mesma cadência. Diferença: Receita (Budget aprovado + Installment) em vez
# de Despesa (Expense).
class CreateFinancialRecurringBillings < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_recurring_billings do |t|
      t.bigint  :account_id,                 null: false
      t.bigint  :patient_id,                 null: false
      t.bigint  :professional_id             # nullable: comissão opcional
      t.bigint  :financial_dre_category_id   # categoria receita; default = receitas
      t.bigint  :payment_method_id,          null: false
      t.bigint  :financial_bank_account_id   # conta destino opcional; senão usa pm.default

      t.string  :description,                null: false, limit: 200
      t.bigint  :amount_cents,               null: false  # valor por período

      # Frequência fixa por enquanto: monthly. Espelha `frequencies` do
      # RecurringExpense pra abrir caminho de bimonthly/quarterly/etc. futuro.
      t.string  :frequency, null: false, default: 'monthly', limit: 20

      t.date    :start_date,                 null: false
      t.date    :end_date                    # nullable = indeterminado

      # Próxima data em que o job deve gerar uma cobrança. Atualizada a cada
      # geração somando 1 frequência. Quando end_date setado e next_generation_at
      # > end_date → status vira `completed`.
      t.date    :next_generation_at,         null: false
      t.datetime :last_generated_at          # trace; nullable até a 1ª geração

      # active = gerando | paused = pausado pelo operador (não gera, retoma depois)
      # completed = atingiu end_date | canceled = encerrado manualmente (irreversível)
      t.string  :status, null: false, default: 'active', limit: 20

      t.text    :notes

      # Audit + lifecycle
      t.bigint   :created_by_id
      t.datetime :paused_at
      t.bigint   :paused_by_id
      t.datetime :canceled_at
      t.bigint   :canceled_by_id
      t.text     :cancel_reason

      # Soft delete (canon do módulo)
      t.datetime :deleted_at
      t.bigint   :deleted_by_id

      t.timestamps
    end

    add_index :financial_recurring_billings, %i[account_id status],
              name: 'idx_rb_account_status'
    add_index :financial_recurring_billings, %i[account_id next_generation_at],
              where: 'deleted_at IS NULL',
              name: 'idx_rb_due_active'
    add_index :financial_recurring_billings, :patient_id
    add_index :financial_recurring_billings, :payment_method_id
    add_index :financial_recurring_billings, :deleted_at
  end
end
