class CreateFinancialV2Configurations < ActiveRecord::Migration[7.0]
  # Tabelas de configuração do módulo financeiro v2.
  # Canon: docs/01-product/modules/financeiro-funcionamento.md §4 (Grupo A — Configurações)
  # e docs/03-engineering/archive/financial-v2-implementation/02-cards-desenvolvimento.md F-01, F-05, F-06, F-07.
  #
  # Convenção:
  # - valores monetários sempre em centavos (BIGINT) — Parte 6 §"Valores em centavos".
  # - soft delete com deleted_at + deleted_by_id em todas as tabelas.
  # - timestamps de auditoria created_by_id / updated_by_id.
  # - account_id obrigatório (multi-tenant) em todas.
  def change
    # ---------------------------------------------------------------
    # Categorias (DRE) — 4 tipos: receita, despesa_fixa, custo_variavel, outra_despesa
    # ---------------------------------------------------------------
    create_table :financial_dre_categories do |t|
      t.bigint  :account_id,    null: false
      t.string  :name,          null: false, limit: 120
      t.string  :kind,          null: false, limit: 30
      # kind: receita | despesa_fixa | custo_variavel | outra_despesa
      t.bigint  :parent_id
      t.string  :color,         limit: 16, default: '#64748b'
      t.string  :icon,          limit: 60, default: 'i-lucide-tag'
      t.boolean :is_default,    default: false, null: false
      t.boolean :active,        default: true, null: false
      t.integer :position,      default: 0, null: false
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_dre_categories, :account_id
    add_index :financial_dre_categories, [:account_id, :kind]
    add_index :financial_dre_categories, [:account_id, :name, :kind], unique: true,
              where: 'deleted_at IS NULL', name: 'idx_uniq_dre_category_per_account'
    add_index :financial_dre_categories, :parent_id
    add_index :financial_dre_categories, :deleted_at

    # ---------------------------------------------------------------
    # Bank accounts — tipos: checking, savings, cash, card_receivable
    # Saldo nunca armazenado, sempre calculado (canon §4.2).
    # ---------------------------------------------------------------
    create_table :financial_bank_accounts do |t|
      t.bigint  :account_id,        null: false
      t.string  :name,              null: false, limit: 120
      t.string  :kind,              null: false, default: 'checking', limit: 30
      # kind: checking | savings | cash | card_receivable
      t.string  :bank_name,         limit: 120
      t.string  :bank_code,         limit: 10
      t.string  :agency,            limit: 20
      t.string  :account_number,    limit: 30
      t.bigint  :initial_balance_cents, null: false, default: 0
      t.boolean :active,            null: false, default: true
      t.integer :card_settlement_days  # CARD_RECEIVABLE: D+N (1, 30...)
      t.string  :gateway_account_id     # Asaas: sub-account id futuro
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_bank_accounts, :account_id
    add_index :financial_bank_accounts, [:account_id, :kind]
    add_index :financial_bank_accounts, [:account_id, :name], unique: true,
              where: 'deleted_at IS NULL', name: 'idx_uniq_bank_account_name_per_account'
    add_index :financial_bank_accounts, :deleted_at

    # ---------------------------------------------------------------
    # Commission rules — vigência por intervalo de datas (canon §4.3)
    # Regra mais recente vigente na data do recebimento é a aplicada.
    # Mudança não recalcula histórico.
    # ---------------------------------------------------------------
    create_table :financial_commission_rules do |t|
      t.bigint  :account_id,           null: false
      t.bigint  :professional_id,      null: false  # User
      t.bigint  :financial_dre_category_id           # se kind=por_categoria
      t.string  :kind,                 null: false, limit: 40
      # kind: percentual_geral | percentual_por_procedimento | percentual_por_especialidade | valor_fixo
      t.string  :base,                 null: false, default: 'recebido', limit: 30
      # base: bruto | recebido | recebido_menos_mdr | recebido_menos_lab
      t.integer :percent_basis_points  # 4000 = 40,00%
      t.bigint  :fixed_amount_cents
      t.string  :procedure_name,       limit: 200
      t.string  :specialty,            limit: 80
      t.boolean :deduct_mdr,           default: false, null: false
      t.boolean :deduct_lab,           default: false, null: false
      t.date    :valid_from,           null: false
      t.date    :valid_until
      t.boolean :active,               default: true, null: false
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_commission_rules, :account_id
    add_index :financial_commission_rules, [:account_id, :professional_id],
              name: 'idx_commission_rules_account_professional'
    add_index :financial_commission_rules, [:professional_id, :valid_from, :valid_until],
              name: 'idx_commission_rules_validity'
    add_index :financial_commission_rules, :deleted_at

    # ---------------------------------------------------------------
    # Recurring expenses — modelo de despesa periódica (canon §4.4)
    # Cron diário gera as despesas dos próximos 35 dias (idempotente).
    # ---------------------------------------------------------------
    create_table :financial_recurring_expenses do |t|
      t.bigint  :account_id,           null: false
      t.string  :name,                 null: false, limit: 200
      t.bigint  :financial_dre_category_id, null: false
      t.bigint  :financial_bank_account_id
      t.bigint  :amount_cents,         null: false
      t.boolean :variable_amount,      default: false, null: false
      t.string  :frequency,            null: false, default: 'monthly', limit: 20
      # frequency: monthly | bimonthly | quarterly | semiannual | annual
      t.integer :due_day,              null: false  # 1..31
      t.string  :competence_rule,      null: false, default: 'same_month', limit: 20
      # competence_rule: same_month | previous_month
      t.date    :start_date,           null: false
      t.date    :end_date
      t.boolean :auto_pay,             default: false, null: false
      t.boolean :active,               default: true, null: false
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_recurring_expenses, :account_id
    add_index :financial_recurring_expenses, [:account_id, :active]
    add_index :financial_recurring_expenses, :deleted_at

    # ---------------------------------------------------------------
    # Revenue goals — 3 metas independentes (mensal, trimestral, anual)
    # ---------------------------------------------------------------
    create_table :financial_revenue_goals do |t|
      t.bigint  :account_id,           null: false
      t.string  :period,               null: false, limit: 20
      # period: monthly | quarterly | annual
      t.integer :year,                 null: false
      t.integer :month                # se monthly
      t.integer :quarter              # se quarterly: 1..4
      t.bigint  :amount_cents,         null: false
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.timestamps
    end
    add_index :financial_revenue_goals, :account_id
    add_index :financial_revenue_goals, [:account_id, :period, :year, :month, :quarter],
              unique: true, name: 'idx_uniq_revenue_goal_per_period'

    # ---------------------------------------------------------------
    # Patient credits — saldo a favor do paciente (canon glossário)
    # Ledger de movimentações; saldo = soma dos amounts agrupados por paciente.
    # ---------------------------------------------------------------
    create_table :financial_patient_credits do |t|
      t.bigint  :account_id,        null: false
      t.bigint  :patient_id,        null: false
      t.bigint  :amount_cents,      null: false
      # > 0 = crédito (entrada de saldo a favor); < 0 = abatimento.
      t.string  :origin,            null: false, limit: 40
      # origin: estorno | pre_pagamento | pagamento_excedente | abatimento_parcela | saque_dinheiro | ajuste_manual
      t.bigint  :origin_id          # ID da entidade que originou (Installment, Entry, etc.)
      t.string  :origin_type        # Financial::Installment, Financial::Entry, ...
      t.text    :description
      t.bigint  :registered_by_id   # User (operador)
      t.datetime :occurred_at,      null: false
      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :financial_patient_credits, :account_id
    add_index :financial_patient_credits, [:account_id, :patient_id]
    add_index :financial_patient_credits, [:account_id, :patient_id, :occurred_at],
              name: 'idx_patient_credits_chronological'
    add_index :financial_patient_credits, [:origin_type, :origin_id]
    add_index :financial_patient_credits, :deleted_at
  end
end
