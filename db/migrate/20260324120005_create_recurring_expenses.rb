class CreateRecurringExpenses < ActiveRecord::Migration[7.0]
  def change
    create_table :recurring_expenses do |t|
      t.bigint  :account_id,             null: false
      t.bigint  :financial_category_id               # categoria ("Aluguel", "Salários")
      t.bigint  :bank_account_id                     # conta de débito
      t.bigint  :registered_by_id                    # quem cadastrou

      t.string  :description,            null: false # "Aluguel — Sala 201"
      t.decimal :amount,                 precision: 12, scale: 2, null: false
      t.string  :payment_method                      # pix/boleto/transferencia etc

      t.string  :frequency,              null: false # 'monthly' / 'weekly' / 'biweekly' / 'quarterly' / 'yearly'
      t.integer :due_day,                default: 1  # dia do vencimento (1-31)
      t.integer :competence_offset_days, default: 0  # offset em dias: competence_date = due_date - offset
      # Ex: aluguel vence dia 10, competência é mês anterior → offset = 10 (ou usar mês anterior)
      t.string  :competence_rule,        default: 'same_month' # 'same_month' / 'previous_month'
      # same_month: competência = mês do vencimento
      # previous_month: competência = mês anterior ao vencimento (ex: aluguel março pago em abril)

      t.date    :start_date,             null: false # quando começa a gerar
      t.date    :end_date                            # quando para (null = indefinido)
      t.date    :last_generated_at                   # última data que gerou account_transaction

      t.boolean :active,                 default: true
      t.boolean :auto_confirm,           default: false # se true, gera já com status 'pago'
      t.text    :notes
      t.timestamps
    end

    add_index :recurring_expenses, :account_id
    add_index :recurring_expenses, :financial_category_id
    add_index :recurring_expenses, :active
    add_index :recurring_expenses, :frequency
  end
end
