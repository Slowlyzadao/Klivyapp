# Adiciona `provider_alias` em `financial_payment_methods` — apelido amigável
# por provedor (ex: "Cielo - Loja Centro"). Compartilhado entre todos os
# métodos do mesmo (account_id, provider): quando operador renomeia "Cielo"
# pra "Cielo - Loja Centro" no header do grupo, controller propaga o alias
# pra todos os payment_methods com mesmo provider/account.
#
# Por que campo na tabela existente em vez de um model PaymentProvider novo?
# - Provider hoje é só string livre; nenhum FK existente
# - Compartilhamento é convenção de UI, não restrição estrutural
# - Migration leve, zero refactor de queries existentes
#
# Index não-único intencional (vários métodos podem ter o mesmo alias).
class AddProviderAliasToFinancialPaymentMethods < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_payment_methods, :provider_alias, :string, limit: 120
    add_index  :financial_payment_methods, %i[account_id provider]
  end
end
