# Cria `financial_payment_method_fees` — taxas versionadas por meio de
# pagamento × quantidade de parcelas × vigência. Canon `mapa-financeiro.json`
# step 3 ("Cada parcela tem sua própria taxa percentual").
#
# Substitui o cálculo hardcoded de MDR em receive_payment.rb (CRIT-CALC-01)
# por lookup dinâmico:
#   fee_for(account_id:, payment_method_id:, installments_count:, date:)
#
# Imutabilidade: nunca editar taxa existente — inativar e criar nova com
# `valid_from` futuro. Lançamentos passados ficam vinculados à taxa vigente
# no momento via FK `payment_method_fee_id` na Installment + snapshot
# congelado `fee_percent_basis_points` (frozen_attributes).
#
# Exclusion constraint via gist: garante que não há 2 taxas ativas
# concorrentes pro mesmo (account, method, installments_count) no mesmo
# período — sem isso, lookup pode pegar registro errado.
class CreateFinancialPaymentMethodFees < ActiveRecord::Migration[7.1]
  def up
    # Pré-requisito do exclusion constraint (gist).
    enable_extension 'btree_gist' unless extension_enabled?('btree_gist')

    create_table :financial_payment_method_fees do |t|
      t.bigint  :account_id,         null: false
      t.bigint  :payment_method_id,  null: false
      t.integer :installments_count, null: false
      # 1..24 — taxa específica pra esta quantidade de parcelas
      t.integer :fee_percent_basis_points, null: false, default: 0
      # 1% = 100bps; 3.5% = 350bps; banker's accuracy
      t.bigint  :fee_fixed_cents, null: false, default: 0
      # ex: boleto = 2.50 fixo, sem percentual
      t.integer :liquidation_days, null: false, default: 0
      # D+0 = 0, D+1 = 1, D+30 = 30

      t.date    :valid_from, null: false
      t.date    :valid_to
      # null = vigente. Imutabilidade: nunca editar; cria nova com valid_from > antigo

      t.string  :status, null: false, default: 'active', limit: 16
      # status: active | inactive

      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :financial_payment_method_fees, :account_id
    add_index :financial_payment_method_fees, :payment_method_id
    add_index :financial_payment_method_fees,
              %i[account_id payment_method_id installments_count valid_from valid_to],
              name: 'idx_payment_method_fees_lookup'

    add_foreign_key :financial_payment_method_fees, :accounts,
                    column: :account_id, on_delete: :restrict
    add_foreign_key :financial_payment_method_fees, :financial_payment_methods,
                    column: :payment_method_id, on_delete: :restrict

    add_check_constraint :financial_payment_method_fees,
                         'installments_count BETWEEN 1 AND 24',
                         name: 'chk_fees_installments_count'
    add_check_constraint :financial_payment_method_fees,
                         'fee_percent_basis_points BETWEEN 0 AND 10000',
                         name: 'chk_fees_percent_range'
    add_check_constraint :financial_payment_method_fees,
                         'fee_fixed_cents >= 0',
                         name: 'chk_fees_fixed_nonneg'
    add_check_constraint :financial_payment_method_fees,
                         'liquidation_days >= 0',
                         name: 'chk_fees_liquidation_nonneg'
    add_check_constraint :financial_payment_method_fees,
                         'valid_to IS NULL OR valid_to >= valid_from',
                         name: 'chk_fees_valid_range'
    add_check_constraint :financial_payment_method_fees,
                         "status IN ('active','inactive')",
                         name: 'chk_fees_status'

    # Exclusion constraint: 2 fees ativos com mesmo (account, method,
    # installments_count) não podem ter intervalos de vigência sobrepostos.
    # `daterange(valid_from, COALESCE(valid_to, 'infinity'::date), '[]')`
    # cobre o caso de fee ativa (valid_to NULL = infinito).
    execute <<~SQL
      ALTER TABLE financial_payment_method_fees
      ADD CONSTRAINT no_overlapping_payment_method_fees
      EXCLUDE USING gist (
        account_id WITH =,
        payment_method_id WITH =,
        installments_count WITH =,
        daterange(valid_from, COALESCE(valid_to, 'infinity'::date), '[]') WITH &&
      )
      WHERE (deleted_at IS NULL AND status = 'active');
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE financial_payment_method_fees
      DROP CONSTRAINT IF EXISTS no_overlapping_payment_method_fees;
    SQL
    drop_table :financial_payment_method_fees
  end
end
