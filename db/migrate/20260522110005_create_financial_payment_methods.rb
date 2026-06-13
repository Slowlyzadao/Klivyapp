# Cria `financial_payment_methods` — meios de pagamento configurados pela
# clínica. Canon `mapa-financeiro.json` step 3.
#
# Substitui o enum hardcoded `Installment.PAYMENT_METHODS` (dinheiro, pix,
# debito, etc) por uma tabela editável: cada clínica pode ter "Cielo Crédito",
# "GetNet Crédito" ou "Pix Itaú" como múltiplos métodos derivados do mesmo
# kind canon. A taxa percentual + por parcela vive em
# `financial_payment_method_fees` (próxima migration), com vigência por data.
#
# Auditoria 2026-05-22 (`CRIT-CALC-01`): MDR hardcoded em receive_payment.rb
# (debito=2%, credito=3,5%) será substituído por lookup nesta tabela +
# `financial_payment_method_fees` com snapshot congelado na Installment.
class CreateFinancialPaymentMethods < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_payment_methods do |t|
      t.bigint  :account_id,  null: false
      t.string  :kind,        null: false, limit: 30
      # kind: dinheiro | pix | debito | credito | boleto | transferencia | convenio | parcelamento_proprio
      t.string  :name,        null: false, limit: 120
      # name: "Cielo Crédito", "Pix Banco Itaú" — display name editável
      t.string  :provider,    limit: 80
      # provider: "Cielo", "GetNet", "Itaú" — informativo

      t.bigint  :default_bank_account_id
      # Conta destino padrão pra recebimentos com este método (routing).

      t.boolean :supports_installments, null: false, default: false
      t.integer :max_installments,      null: false, default: 1
      # 1..24 — quantidade máxima de parcelas suportada (cartão = 12, boleto/pix = 1)

      t.string  :status, null: false, default: 'active', limit: 16
      # status: active | inactive — inativar não deleta histórico

      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :financial_payment_methods, :account_id
    add_index :financial_payment_methods, %i[account_id kind] # lookup rápido por canon kind
    add_index :financial_payment_methods, %i[account_id status]
    add_index :financial_payment_methods, %i[account_id name], unique: true,
              where: 'deleted_at IS NULL',
              name: 'idx_uniq_payment_method_account_name'

    add_foreign_key :financial_payment_methods, :accounts, column: :account_id, on_delete: :restrict
    add_foreign_key :financial_payment_methods, :financial_bank_accounts,
                    column: :default_bank_account_id, on_delete: :restrict

    add_check_constraint :financial_payment_methods,
                         "kind IN ('dinheiro','pix','debito','credito','boleto','transferencia','convenio','parcelamento_proprio')",
                         name: 'chk_payment_methods_kind'
    add_check_constraint :financial_payment_methods,
                         'max_installments BETWEEN 1 AND 24',
                         name: 'chk_payment_methods_max_installments'
    add_check_constraint :financial_payment_methods,
                         "status IN ('active','inactive')",
                         name: 'chk_payment_methods_status'
  end
end
