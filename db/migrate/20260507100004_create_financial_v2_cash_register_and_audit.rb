class CreateFinancialV2CashRegisterAndAudit < ActiveRecord::Migration[7.0]
  # Caixa físico (sessão diária) + AuditLog automático.
  # Canon: 01-funcionamento §4.8 (Caixa) + Parte 6 (audit log).
  def change
    # ---------------------------------------------------------------
    # Cash registers — sessão diária do caixa físico.
    # Apenas 1 caixa OPEN por dia por account. Bloqueia lançamento em dinheiro
    # com data em sessão fechada (canon §4.8).
    # ---------------------------------------------------------------
    create_table :financial_cash_registers do |t|
      t.bigint  :account_id,                       null: false
      t.bigint  :financial_bank_account_id,        null: false  # type=cash
      t.bigint  :operator_id,                      null: false  # User
      t.date    :session_date,                     null: false
      t.string  :status,               null: false, default: 'open', limit: 16
      # status: open | closed
      t.bigint  :opening_balance_cents,            null: false, default: 0
      t.bigint  :expected_balance_cents            # calculado no fechamento
      t.bigint  :counted_balance_cents             # contado pelo operador no fechamento
      t.bigint  :difference_cents,     default: 0  # counted - expected (negativo = falta)
      t.text    :opening_note
      t.text    :closing_note
      t.text    :reopen_reason
      t.datetime :opened_at,            null: false
      t.datetime :closed_at
      t.bigint  :closed_by_id
      t.datetime :reopened_at
      t.bigint  :reopened_by_id
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_cash_registers, :account_id
    add_index :financial_cash_registers, [:account_id, :status, :session_date],
              name: 'idx_cash_registers_account_status_date'
    add_index :financial_cash_registers, [:account_id, :financial_bank_account_id, :session_date],
              unique: true, where: "status = 'open' AND deleted_at IS NULL",
              name: 'idx_uniq_open_cash_register_per_day'
    add_index :financial_cash_registers, :operator_id
    add_index :financial_cash_registers, :deleted_at

    # ---------------------------------------------------------------
    # Cash movements — sangria, suprimento, quebra de caixa.
    # Sangria: dinheiro sai do caixa físico para conta bancária. (transferência neutra)
    # Suprimento: inverso (banco → caixa). (transferência neutra)
    # Quebra: registrada no fechamento, lança em Outras Despesas (falta) ou Outras Receitas (sobra).
    # ---------------------------------------------------------------
    create_table :financial_cash_movements do |t|
      t.bigint  :account_id,                       null: false
      t.bigint  :financial_cash_register_id,       null: false
      t.bigint  :financial_bank_account_id          # destino da sangria / origem do suprimento
      t.string  :kind,                 null: false, limit: 20
      # kind: sangria | suprimento | quebra_falta | quebra_sobra
      t.bigint  :amount_cents,         null: false
      t.bigint  :financial_entry_in_id   # entry do lado IN gerado pelo movimento
      t.bigint  :financial_entry_out_id  # entry do lado OUT gerado pelo movimento
      t.text    :notes
      t.datetime :occurred_at,         null: false
      t.bigint  :registered_by_id      # User (operador)
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_cash_movements, :account_id
    add_index :financial_cash_movements, :financial_cash_register_id, name: 'idx_cash_movements_on_register'
    add_index :financial_cash_movements, [:account_id, :kind]
    add_index :financial_cash_movements, :deleted_at

    # ---------------------------------------------------------------
    # Audit logs — registra TODA escrita em entidade financeira.
    # Canon Parte 6 + BUG-12. Inserção async para não bloquear transação principal.
    # ---------------------------------------------------------------
    create_table :financial_audit_logs do |t|
      t.bigint  :account_id,                       null: false
      t.bigint  :user_id                           # quem fez (null se job/sistema)
      t.string  :entity_type,          null: false, limit: 80
      t.bigint  :entity_id,            null: false
      t.string  :action,               null: false, limit: 30
      # action: create | update | destroy | restore | denied | login | logout | export
      t.string  :ip_address,           limit: 45
      t.string  :user_agent
      t.jsonb   :before,               default: {}
      t.jsonb   :after,                default: {}
      t.jsonb   :metadata,             default: {}  # idempotency_key, request_id, etc.
      t.datetime :created_at,          null: false
    end
    add_index :financial_audit_logs, :account_id
    add_index :financial_audit_logs, [:account_id, :entity_type, :entity_id],
              name: 'idx_audit_logs_on_entity'
    add_index :financial_audit_logs, [:account_id, :user_id, :created_at],
              name: 'idx_audit_logs_account_user_chronological'
    add_index :financial_audit_logs, [:account_id, :created_at]
    add_index :financial_audit_logs, [:account_id, :action]
  end
end
