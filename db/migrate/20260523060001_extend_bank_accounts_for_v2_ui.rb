# Estende `financial_bank_accounts` com campos do wireframe canon
# "Contas Bancárias e Caixas" — Setup #4:
#
#   - `cnpj`                    PJ titular (texto livre, sem máscara)
#   - `pix_key`                 chave PIX cadastrada na conta
#   - `cut_date`                "Data de Corte" — referência pra extrato/fatura
#   - `color`                   cor visual pra identificação na lista (paleta canon)
#   - `default_for_receivables` única conta default pra recebimentos (badge RECEB)
#   - `default_for_payments`    única conta default pra pagamentos (badge PGTO)
#
# Unicidade de `default_for_*` é garantida via partial unique index:
# `WHERE flag = true AND deleted_at IS NULL`. Rails-level também valida
# (defense in depth) — ver `Financial::BankAccount`.
class ExtendBankAccountsForV2Ui < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_bank_accounts, :cnpj,                    :string, limit: 20
    add_column :financial_bank_accounts, :pix_key,                 :string, limit: 120
    add_column :financial_bank_accounts, :cut_date,                :date
    add_column :financial_bank_accounts, :color,                   :string, limit: 16, default: '#3b82f6', null: false
    add_column :financial_bank_accounts, :default_for_receivables, :boolean, default: false, null: false
    add_column :financial_bank_accounts, :default_for_payments,    :boolean, default: false, null: false

    add_index :financial_bank_accounts,
              [:account_id],
              unique: true,
              where: 'default_for_receivables = true AND deleted_at IS NULL',
              name: 'idx_uniq_bank_default_receivables_per_account'

    add_index :financial_bank_accounts,
              [:account_id],
              unique: true,
              where: 'default_for_payments = true AND deleted_at IS NULL',
              name: 'idx_uniq_bank_default_payments_per_account'
  end
end
