# Adiciona `settlement_mode` em `financial_payment_methods` - politica de
# baixa por forma de pagamento. Decisao 2026-05-27 (memory
# project_baixa_automatica_cartao).
#
# Modos:
#   - manual       -> operador clica "Receber" (default seguro). Boleto,
#                     convenio, parcelamento proprio: a clinica assume o risco
#                     de cobranca, entao NAO pode dar baixa automatica.
#   - on_confirm   -> baixa na confirmacao do wizard de aprovacao (a vista:
#                     dinheiro/PIX/debito - operador viu o dinheiro entrar).
#   - on_due_date  -> baixa automatica na data, via AutoSettleCardInstallmentsJob.
#                     SO p/ cartao de credito/debito: a adquirente garante o
#                     repasse, e o operador ja confirmou ao passar na maquininha.
#
# Guardrail `on_due_date` em {credito, debito} e validado no model
# (PaymentMethod#auto_settle_only_for_card_kinds).
#
# Backfill por kind pra entregar o comportamento pedido sem o operador ter
# que reconfigurar cada metodo: credito -> on_due_date; dinheiro/PIX/debito ->
# on_confirm; resto -> manual. Operador ajusta caso a caso em Settings.
class AddSettlementModeToFinancialPaymentMethods < ActiveRecord::Migration[7.1]
  def up
    add_column :financial_payment_methods, :settlement_mode, :string,
               limit: 20, default: 'manual', null: false

    # Backfill - so toca o que existe; default cuida dos novos.
    execute <<~SQL.squish
      UPDATE financial_payment_methods SET settlement_mode = 'on_due_date'
      WHERE kind = 'credito'
    SQL
    execute <<~SQL.squish
      UPDATE financial_payment_methods SET settlement_mode = 'on_confirm'
      WHERE kind IN ('dinheiro', 'pix', 'debito')
    SQL
  end

  def down
    remove_column :financial_payment_methods, :settlement_mode
  end
end
