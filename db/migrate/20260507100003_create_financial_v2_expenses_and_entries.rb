class CreateFinancialV2ExpensesAndEntries < ActiveRecord::Migration[7.0]
  # Expenses (A Pagar) e FinancialEntries (lançamentos efetivos no fluxo de caixa).
  # Canon: 01-funcionamento §4.7 (A Pagar) + Parte 6 (regime caixa vs competência).
  #
  # FinancialEntry é o ledger central de movimentações efetivas — tem competence_date
  # (DRE, regime competência) E cash_date (Fluxo, regime caixa) sempre populados.
  def change
    # ---------------------------------------------------------------
    # Expenses — A Pagar.
    # Pode ser avulsa, originada de uma RecurringExpense, ou origem de comissão profissional.
    # ---------------------------------------------------------------
    create_table :financial_expenses do |t|
      t.bigint  :account_id,                       null: false
      t.bigint  :financial_dre_category_id,        null: false
      t.bigint  :financial_bank_account_id          # conta de origem do pagamento
      t.bigint  :financial_recurring_expense_id     # se origem recorrente
      t.bigint  :financial_commission_entry_id      # se origem é comissão a pagar a profissional
      t.bigint  :supplier_id                        # opcional (futuro: tabela de fornecedores)
      t.string  :supplier_name,        limit: 200   # snapshot do nome no momento
      t.string  :description,          null: false, limit: 240
      t.string  :status,               null: false, default: 'pendente', limit: 20
      # status: pendente | pago | vencido | estornado | cancelado
      t.bigint  :amount_cents,         null: false
      t.bigint  :paid_amount_cents,    null: false, default: 0
      t.string  :payment_method,       limit: 30
      t.date    :competence_date,      null: false
      t.date    :due_date,             null: false
      t.date    :paid_at
      t.bigint  :installments_count,   default: 1
      t.bigint  :installment_number,   default: 1
      t.bigint  :parent_expense_id      # para parcelas de despesa parcelada
      t.string  :external_id,          limit: 60   # importação Clinicorp
      t.text    :notes
      t.jsonb   :metadata,             default: {}

      # Asaas / gateway (futuro: pagamento de fornecedores via Pix Asaas)
      t.string  :gateway,              limit: 30, default: 'manual'
      t.string  :gateway_id,           limit: 100
      t.string  :gateway_status,       limit: 40
      t.jsonb   :gateway_metadata,     default: {}
      t.datetime :gateway_synced_at

      t.bigint  :registered_by_id
      t.bigint  :paid_by_id
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_expenses, :account_id
    add_index :financial_expenses, [:account_id, :status]
    add_index :financial_expenses, [:account_id, :status, :due_date],
              name: 'idx_expenses_account_status_due'
    add_index :financial_expenses, [:account_id, :competence_date],
              name: 'idx_expenses_account_competence'
    add_index :financial_expenses, :financial_dre_category_id, name: 'idx_expenses_on_category'
    add_index :financial_expenses, :financial_recurring_expense_id, name: 'idx_expenses_on_recurring'
    add_index :financial_expenses, :financial_commission_entry_id, name: 'idx_expenses_on_commission_entry'
    add_index :financial_expenses, :parent_expense_id
    add_index :financial_expenses, [:account_id, :external_id], unique: true,
              where: 'external_id IS NOT NULL', name: 'idx_uniq_expense_external_id'
    add_index :financial_expenses, :deleted_at

    # ---------------------------------------------------------------
    # Financial entries — ledger central. UM lançamento de fluxo efetivo.
    # Toda entrada/saída/transferência efetiva passa por aqui.
    # cash_date dirige Fluxo de Caixa; competence_date dirige DRE.
    # ---------------------------------------------------------------
    create_table :financial_entries do |t|
      t.bigint  :account_id,                       null: false
      t.bigint  :financial_bank_account_id,        null: false
      t.bigint  :financial_dre_category_id          # null se transfer (neutro no DRE)
      t.bigint  :patient_id                         # se vinculado a paciente
      t.bigint  :professional_id                    # se vinculado a profissional
      t.string  :direction,            null: false, limit: 10
      # direction: in | out
      t.string  :kind,                 null: false, limit: 30
      # kind: receita | despesa | transferencia | sangria | suprimento | quebra_caixa | estorno_receita | estorno_despesa | juros | multa | desconto
      t.bigint  :amount_cents,         null: false
      t.string  :payment_method,       limit: 30
      t.date    :competence_date,      null: false  # regime competência (DRE)
      t.date    :cash_date,            null: false  # regime caixa (Fluxo)
      t.string  :description,          null: false, limit: 240

      # vínculos polimórficos opcionais com a origem do lançamento
      t.string  :source_type,          limit: 60
      # source_type: Financial::PaymentReceipt | Financial::Expense | Financial::CashMovement
      t.bigint  :source_id

      # transferência interna: aponta para o entry par
      t.bigint  :transfer_pair_id

      # estorno: aponta para o entry sendo revertido
      t.bigint  :reverses_entry_id

      t.boolean :affects_dre,          null: false, default: true
      # transferência (sangria/suprimento) marca affects_dre=false → DRE ignora.
      t.boolean :affects_cashflow,     null: false, default: true

      t.bigint  :cash_register_id      # se ocorreu durante sessão de caixa físico

      t.jsonb   :metadata,             default: {}

      t.bigint  :registered_by_id      # User (operador)
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_entries, :account_id
    add_index :financial_entries, [:account_id, :direction]
    add_index :financial_entries, [:account_id, :cash_date],
              name: 'idx_entries_account_cash_date'
    add_index :financial_entries, [:account_id, :competence_date, :affects_dre],
              name: 'idx_entries_account_competence_dre'
    add_index :financial_entries, :financial_bank_account_id, name: 'idx_entries_on_bank_account'
    add_index :financial_entries, :financial_dre_category_id, name: 'idx_entries_on_category'
    add_index :financial_entries, :patient_id
    add_index :financial_entries, :professional_id
    add_index :financial_entries, [:source_type, :source_id]
    add_index :financial_entries, :transfer_pair_id, where: 'transfer_pair_id IS NOT NULL'
    add_index :financial_entries, :reverses_entry_id, where: 'reverses_entry_id IS NOT NULL'
    add_index :financial_entries, :cash_register_id, where: 'cash_register_id IS NOT NULL'
    add_index :financial_entries, :deleted_at

    # ---------------------------------------------------------------
    # Commission entries — comissão devida ao profissional.
    # Status canon: provisionada (parcela pendente) | devida (recebida) | paga (quitada com profissional).
    # ---------------------------------------------------------------
    create_table :financial_commission_entries do |t|
      t.bigint  :account_id,                       null: false
      t.bigint  :professional_id,                  null: false
      t.bigint  :financial_installment_id          # origem: parcela recebida
      t.bigint  :financial_commission_rule_id      # regra aplicada (snapshot)
      t.bigint  :financial_payment_receipt_id      # se a parcela foi quitada via receipt
      t.string  :status,               null: false, default: 'provisionada', limit: 20
      # status: provisionada | devida | paga | estornada
      t.bigint  :base_amount_cents,    null: false
      t.bigint  :mdr_deduction_cents,  null: false, default: 0
      t.bigint  :lab_deduction_cents,  null: false, default: 0
      t.bigint  :calc_base_cents,      null: false  # base usada para o cálculo (após deduções)
      t.integer :percent_basis_points  # snapshot da regra
      t.bigint  :commission_amount_cents, null: false
      t.date    :competence_date,      null: false  # data do recebimento original
      t.date    :paid_at
      t.bigint  :paid_by_id
      t.bigint  :financial_expense_id  # se foi paga via Expense
      t.bigint  :reverses_entry_id     # se status=estornada
      t.text    :notes
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_commission_entries, :account_id
    add_index :financial_commission_entries, [:account_id, :professional_id],
              name: 'idx_commission_entries_on_professional'
    add_index :financial_commission_entries, [:account_id, :status]
    add_index :financial_commission_entries, :financial_installment_id,
              name: 'idx_commission_entries_on_installment'
    add_index :financial_commission_entries, :financial_payment_receipt_id,
              name: 'idx_commission_entries_on_receipt'
    add_index :financial_commission_entries, :deleted_at
  end
end
