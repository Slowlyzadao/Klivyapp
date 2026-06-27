# Pagamento dividido (multi-cartao/multi-forma) + baixa automatica.
# Canon: docs/03-engineering/financeiro-fluxo-aprovacao-parcelamento.md (F4)
# Decisao de produto 2026-05-27 (memory project_baixa_automatica_cartao).
#
# - `card_installments`: parcelamento DESSA perna na maquininha. Ex.: numa
#   divisao "R$800 Cielo em 3x + R$250 Stone em 1x", a perna da Cielo tem
#   card_installments=3 e a da Stone =1. E o que o MDR realmente usa - nao
#   o tamanho do plano (`total_in_series`), que antes era usado pra todas as
#   parcelas e mentia a taxa no cenario multi-cartao.
#   NULL = usa `total_in_series` como antes (retrocompat para planos uniformes
#   onde plano inteiro = 1 transacao Nx).
#
# - `tender_group`: agrupa as pernas pagas no MESMO momento (ex.: entrada de
#   R$200 no PIX + R$800 num cartao + R$250 noutro, todas hoje). UUID gerado
#   pelo wizard por grupo de mesma data. NULL para parcelas avulsas/legadas.
#
# - `auto_settled`: marca que a baixa (status `recebido`) foi PROGRAMATICA
#   (AutoSettleCardInstallmentsJob ou auto-receber on_confirm), nao conferida
#   por operador nem por gateway. Conciliacao contra o extrato da adquirente
#   filtra por essa flag pra pegar swipe que recusou/divergiu. Mantem a regra
#   "status nunca mente sucesso" auditavel mesmo sem transacao real validada.
class AddCardInstallmentsAndSettlementToFinancialInstallments < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_installments, :card_installments, :integer, null: true
    add_column :financial_installments, :tender_group, :uuid, null: true
    add_column :financial_installments, :auto_settled, :boolean, default: false, null: false

    add_index :financial_installments, :tender_group,
              where: 'tender_group IS NOT NULL',
              name: 'idx_financial_installments_tender_group'
  end
end
