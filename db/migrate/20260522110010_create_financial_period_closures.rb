# Cria `financial_period_closures` — fechamento de mês contábil.
#
# Conceito (doc `financial-2026-05-implementation.md` §9): após exportar o
# DRE de um mês para o contador, o mês "trava" — edição retroativa em Entry,
# Installment, Expense com competence/cash_date dentro do período é
# bloqueada via validação `period_not_closed` nos models.
#
# Reabertura é processo formal: apenas ADMIN, com motivo obrigatório, e
# gera audit log. Mantém histórico de fechamentos e reaberturas pra
# compliance contábil.
#
# Sem soft-delete: é registro de evento (append-only conceitualmente);
# reabertura é update do mesmo registro com status='reopened' + reopened_at.
class CreateFinancialPeriodClosures < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_period_closures do |t|
      t.bigint  :account_id,    null: false
      t.integer :period_year,   null: false
      t.integer :period_month,  null: false
      # period_year + period_month identificam o mês contábil fechado

      t.datetime :closed_at,    null: false
      t.bigint   :closed_by_id, null: false
      t.text     :notes

      # Reabertura — quando aplicável
      t.datetime :reopened_at
      t.bigint   :reopened_by_id
      t.text     :reopen_reason

      t.string :status, null: false, default: 'closed', limit: 16
      # status: closed | reopened
      # Quando reopened, validação period_not_closed deixa de bloquear edição
      # (mês fica permanentemente em estado "houve reabertura" — fechamento
      # subsequente cria novo registro pra preservar trilha)

      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :financial_period_closures, :account_id
    add_index :financial_period_closures, %i[account_id period_year period_month status],
              unique: true,
              where: "status = 'closed'",
              name: 'idx_uniq_period_closure_active'
    add_index :financial_period_closures, %i[account_id period_year period_month],
              name: 'idx_period_closures_lookup'

    add_foreign_key :financial_period_closures, :accounts,
                    column: :account_id, on_delete: :restrict
    add_foreign_key :financial_period_closures, :users,
                    column: :closed_by_id, on_delete: :restrict
    add_foreign_key :financial_period_closures, :users,
                    column: :reopened_by_id, on_delete: :restrict

    add_check_constraint :financial_period_closures,
                         'period_year BETWEEN 2020 AND 2100',
                         name: 'chk_period_closures_year_range'
    add_check_constraint :financial_period_closures,
                         'period_month BETWEEN 1 AND 12',
                         name: 'chk_period_closures_month_range'
    add_check_constraint :financial_period_closures,
                         "status IN ('closed','reopened')",
                         name: 'chk_period_closures_status'
    add_check_constraint :financial_period_closures,
                         "status != 'reopened' OR (reopened_at IS NOT NULL AND reopened_by_id IS NOT NULL AND reopen_reason IS NOT NULL)",
                         name: 'chk_period_closures_reopen_complete'
  end
end
