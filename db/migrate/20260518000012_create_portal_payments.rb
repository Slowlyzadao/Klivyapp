# Pagamentos iniciados pelo paciente via portal (PRD §9, Sprint F).
#
# Camada de tracking que vive ENTRE o paciente e o gateway. Quando o paciente
# clica em "Pagar com PIX", criamos um `PortalPayment` (status: pending), pedimos
# ao gateway o QR code, persistimos a resposta, e ficamos aguardando o webhook
# do gateway confirmar. Quando confirma, mudamos status pra `paid` e marcamos
# a `Financial::Installment` como recebida via `Financial::ReceivePayment`.
#
# Por que não usar `Financial::Installment` direto? Porque uma parcela pode ter
# múltiplas tentativas de pagamento (PIX expira, paciente tenta de novo via
# boleto, depois cartão). Cada tentativa é um PortalPayment; só uma vence.
class CreatePortalPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_payments do |t|
      t.references :account,                   null: false, foreign_key: true
      t.references :patient,                   null: false, foreign_key: true
      t.references :financial_installment,     null: false, foreign_key: true

      # 'pix' | 'boleto' | 'credit_card'
      t.string   :method, null: false

      # 'pending'         — criado, ainda buscando dados no gateway
      # 'awaiting_payment'— gateway respondeu, dados disponíveis para o paciente
      # 'paid'            — confirmado
      # 'failed'          — gateway rejeitou
      # 'expired'         — passou do prazo sem pagamento
      # 'cancelled'       — paciente desistiu
      t.string   :status, null: false, default: 'pending'

      # 'mock' em dev | 'asaas' em prod (mesmo enum da Financial::GatewaySetting)
      t.string   :gateway, null: false, default: 'mock'

      # ID retornado pelo gateway — chave de idempotência pra reconciliar webhook.
      t.string   :gateway_payment_id, index: { unique: true, where: "gateway_payment_id IS NOT NULL" }

      # Snapshots dos dados do gateway pra renderizar a tela sem 2ª chamada.
      t.text     :pix_qr_code         # base64 PNG ou string PIX copia-cola
      t.text     :pix_copy_paste      # texto pra "copia e cola"
      t.string   :boleto_url
      t.string   :boleto_barcode      # linha digitável
      t.integer  :amount_cents,       null: false

      t.datetime :expires_at
      t.datetime :paid_at

      # Resposta crua do gateway pra debug — não confiar pra lógica.
      t.jsonb    :gateway_payload, default: {}

      t.timestamps

      t.index [:patient_id, :status]
      t.index [:financial_installment_id, :status],
              name: 'idx_portal_payments_installment_status'
    end
  end
end
