# Adiciona colunas de snapshot necessárias para Fase 3 do refactor canon.
#
# Sem essas colunas, o `frozen_attributes` declarado nos models V2 (Fase 1B)
# fica órfão — declaração existe mas a coluna não. Cause: na Fase 1B mexi nos
# models antes de adicionar as colunas. Esta migration fecha o gap.
#
# Adiciona em `financial_installments`:
#   - payment_method_id            → FK pra financial_payment_methods
#   - payment_method_fee_id        → FK pra financial_payment_method_fees
#   - fee_percent_basis_points     → snapshot congelado da taxa percentual
#   - fee_fixed_cents              → snapshot congelado da taxa fixa
#   - fee_amount_cents             → valor calculado da taxa (snapshot)
#   - net_amount_cents             → amount - fee
#   - expected_liquidation_date    → data prevista de liquidação (D+N)
#
# Adiciona em `financial_commission_entries`:
#   - rule_snapshot (jsonb)        → snapshot completo da regra de comissão
#   - triggered_at                 → momento do gatilho que gerou esta comissão
#   - reverses_commission_entry_id → FK self-referencial (estorno proporcional)
#   - approved_at + approved_by_id → workflow Aprovada
#   - financial_budget_id          → vínculo direto ao budget (denormalizado)
#
# Canon: tudo é snapshot histórico — mudar regra/taxa NÃO altera comissões
# já geradas. `attr_readonly` (frozen_attributes) + check_constraint do banco
# protegem contra alteração acidental.
class AddSnapshotColumnsForPhase3 < ActiveRecord::Migration[7.1]
  def up
    # ─── financial_installments: snapshot de taxa ──────────────────────────
    unless column_exists?(:financial_installments, :payment_method_id)
      add_column :financial_installments, :payment_method_id, :bigint
      add_index  :financial_installments, :payment_method_id
      add_foreign_key :financial_installments, :financial_payment_methods,
                      column: :payment_method_id, on_delete: :restrict
    end

    unless column_exists?(:financial_installments, :payment_method_fee_id)
      add_column :financial_installments, :payment_method_fee_id, :bigint
      add_index  :financial_installments, :payment_method_fee_id
      add_foreign_key :financial_installments, :financial_payment_method_fees,
                      column: :payment_method_fee_id, on_delete: :restrict
    end

    unless column_exists?(:financial_installments, :fee_percent_basis_points)
      add_column :financial_installments, :fee_percent_basis_points, :integer
    end

    unless column_exists?(:financial_installments, :fee_fixed_cents)
      add_column :financial_installments, :fee_fixed_cents, :bigint
    end

    unless column_exists?(:financial_installments, :fee_amount_cents)
      add_column :financial_installments, :fee_amount_cents, :bigint, default: 0, null: false
    end

    unless column_exists?(:financial_installments, :net_amount_cents)
      add_column :financial_installments, :net_amount_cents, :bigint, default: 0, null: false
    end

    unless column_exists?(:financial_installments, :expected_liquidation_date)
      add_column :financial_installments, :expected_liquidation_date, :date
    end

    # Check constraints
    unless constraint_exists?('financial_installments', 'chk_installment_fee_pct_range')
      add_check_constraint :financial_installments,
                           'fee_percent_basis_points IS NULL OR fee_percent_basis_points BETWEEN 0 AND 10000',
                           name: 'chk_installment_fee_pct_range'
    end
    unless constraint_exists?('financial_installments', 'chk_installment_fee_fixed_nonneg')
      add_check_constraint :financial_installments,
                           'fee_fixed_cents IS NULL OR fee_fixed_cents >= 0',
                           name: 'chk_installment_fee_fixed_nonneg'
    end
    unless constraint_exists?('financial_installments', 'chk_installment_fee_amount_nonneg')
      add_check_constraint :financial_installments,
                           'fee_amount_cents >= 0',
                           name: 'chk_installment_fee_amount_nonneg'
    end
    unless constraint_exists?('financial_installments', 'chk_installment_net_nonneg')
      add_check_constraint :financial_installments,
                           'net_amount_cents >= 0',
                           name: 'chk_installment_net_nonneg'
    end

    # ─── financial_commission_entries: snapshot da regra ───────────────────
    unless column_exists?(:financial_commission_entries, :rule_snapshot)
      add_column :financial_commission_entries, :rule_snapshot, :jsonb, default: {}, null: false
    end

    unless column_exists?(:financial_commission_entries, :triggered_at)
      add_column :financial_commission_entries, :triggered_at, :timestamp
      # Backfill = competence_date para entries existentes
      execute <<~SQL
        UPDATE financial_commission_entries
        SET triggered_at = COALESCE(competence_date::timestamp, created_at)
        WHERE triggered_at IS NULL;
      SQL
      change_column_null :financial_commission_entries, :triggered_at, false
    end

    unless column_exists?(:financial_commission_entries, :reverses_commission_entry_id)
      add_column :financial_commission_entries, :reverses_commission_entry_id, :bigint
      add_index  :financial_commission_entries, :reverses_commission_entry_id,
                 where: 'reverses_commission_entry_id IS NOT NULL',
                 name: 'idx_commission_entries_reverses'
      add_foreign_key :financial_commission_entries, :financial_commission_entries,
                      column: :reverses_commission_entry_id, on_delete: :restrict
    end

    unless column_exists?(:financial_commission_entries, :approved_at)
      add_column :financial_commission_entries, :approved_at, :timestamp
    end

    unless column_exists?(:financial_commission_entries, :approved_by_id)
      add_column :financial_commission_entries, :approved_by_id, :bigint
      add_foreign_key :financial_commission_entries, :users,
                      column: :approved_by_id, on_delete: :nullify
    end

    unless column_exists?(:financial_commission_entries, :financial_budget_id)
      add_column :financial_commission_entries, :financial_budget_id, :bigint
      add_index  :financial_commission_entries, :financial_budget_id,
                 where: 'financial_budget_id IS NOT NULL'
      add_foreign_key :financial_commission_entries, :financial_budgets,
                      column: :financial_budget_id, on_delete: :restrict
      # Backfill: budget vem do installment quando disponível
      execute <<~SQL
        UPDATE financial_commission_entries c
        SET financial_budget_id = i.financial_budget_id
        FROM financial_installments i
        WHERE c.financial_installment_id = i.id
          AND c.financial_budget_id IS NULL;
      SQL
    end

    # Idempotência: unique index pra evitar duplicar comissão da mesma
    # (regra × installment × profissional). Auditoria 2026-05: PayCommission
    # podia duplicar Expense em retry — esse index é a 2ª camada de defesa
    # (1ª é a checagem `paid_via_expense_id.present?` no service).
    unless index_exists?(:financial_commission_entries,
                        %i[account_id financial_installment_id financial_commission_rule_id professional_id],
                        name: 'idx_uniq_commission_entry_per_rule_inst_prof')
      add_index :financial_commission_entries,
                %i[account_id financial_installment_id financial_commission_rule_id professional_id],
                unique: true,
                where: "financial_installment_id IS NOT NULL AND deleted_at IS NULL AND status != 'estornada' AND reverses_commission_entry_id IS NULL",
                name: 'idx_uniq_commission_entry_per_rule_inst_prof'
    end
  end

  def down
    # Forward-only: snapshot columns são histórico financeiro. Rollback
    # significaria apagar dados de auditoria.
    raise ActiveRecord::IrreversibleMigration,
          'Snapshot columns são append-only — não há rollback. Restaurar via backup se necessário.'
  end

  private

  def constraint_exists?(table, name)
    ActiveRecord::Base.connection.select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM information_schema.check_constraints
      WHERE constraint_name = '#{name}'
    SQL
  end
end
