class CreateAccountTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :account_transactions do |t|
      t.bigint  :account_id,           null: false
      t.bigint  :patient_id                              # opcional (quando vinculado)
      t.bigint  :financial_category_id                   # categoria da despesa/receita
      t.bigint  :bank_account_id                         # conta bancária destino/origem
      t.bigint  :registered_by_id                        # user que registrou
      t.bigint  :professional_id                         # profissional vinculado (faturamento)
      t.bigint  :source_transaction_id                   # link para Transaction do paciente (idempotência)
      t.bigint  :recurring_expense_id                    # link para RecurringExpense que gerou este lançamento
      t.bigint  :estorno_de_id                           # FK → account_transactions (estorno vinculado)

      t.string  :entry_type,           null: false       # 'entrada' / 'saida'
      t.decimal :amount,               precision: 12, scale: 2, null: false
      t.decimal :original_amount,      precision: 12, scale: 2  # valor antes desconto (DRE)
      t.decimal :discount_amount,      precision: 12, scale: 2, default: 0.0
      t.string  :payment_method                          # pix/cartao_credito/etc
      t.string  :status,               null: false, default: 'pendente'
      # pendente / recebido / pago / cancelado / parcial

      # OS 5 CAMPOS DE DATA (spec.financeiro.md seção Regras Gerais)
      t.date    :competence_date                         # data_competencia (DRE — regime competência)
      t.date    :due_date                                # data_vencimento
      t.date    :received_at                             # data_recebimento (receitas — regime caixa)
      t.date    :paid_at                                 # data_pagamento (despesas — regime caixa)
      # created_at = data_criacao (Rails default)

      t.text    :description
      t.text    :notes
      t.string  :origin                                  # 'manual' / 'orcamento' / 'procedimento' / 'recorrente'
      # NOTA: is_recurring e recurrence_rule foram REMOVIDOS.
      # A recorrência é modelada pela tabela `recurring_expenses` (template).
      # Transações geradas automaticamente têm origin='recorrente' + recurring_expense_id preenchido.

      t.jsonb   :metadata,             default: {}
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :account_transactions, :account_id
    add_index :account_transactions, :patient_id
    add_index :account_transactions, :financial_category_id
    add_index :account_transactions, :bank_account_id
    add_index :account_transactions, :recurring_expense_id
    add_index :account_transactions, :source_transaction_id, unique: true  # idempotência
    add_index :account_transactions, :status
    add_index :account_transactions, :due_date
    add_index :account_transactions, :competence_date
    add_index :account_transactions, :entry_type
    add_index :account_transactions, :deleted_at
    add_index :account_transactions, [:account_id, :entry_type, :status], name: 'idx_acct_txns_account_type_status'
    add_index :account_transactions, [:account_id, :competence_date], name: 'idx_acct_txns_account_competence'  # DRE queries
  end
end
