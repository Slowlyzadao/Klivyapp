# Quando um PortalPayment confirma, este service:
#   1. Marca `Financial::Installment` como recebida (via reuse de Financial::ReceivePayment
#      quando possível; fallback pra update direto).
#   2. Gera um `Document` (tipo recibo) anexado ao paciente — vira visível no
#      portal automaticamente.
#   3. Dispatcha notificação in-app pro paciente.
#
# Idempotente: chamado pelo webhook (real ou mock) com payment já confirmado.
# Se rodar 2x pra mesma payment, não duplica recibo.
module PatientPortal
  class PaymentReceiptIssuer
    def initialize(payment:)
      @payment     = payment
      @installment = payment.installment
      @patient     = payment.patient
      @account     = payment.account
    end

    def call
      raise 'PortalPayment deve estar paid' unless @payment.paid?

      ActiveRecord::Base.transaction do
        update_installment!
        document = issue_receipt_document!
        notify!(document)
        document
      end
    end

    private

    def update_installment!
      return if @installment.status == 'recebido'

      received_at = @payment.paid_at || Time.current
      method_map  = { 'pix' => 'pix', 'boleto' => 'boleto', 'credit_card' => 'credito' }
      @installment.update!(
        status:                 'recebido',
        received_amount_cents:  @installment.amount_cents,
        received_at:            received_at,
        payment_method:         method_map[@payment.method] || @installment.payment_method
      )
    end

    def issue_receipt_document!
      # Idempotência: se já existe Document do tipo `recibo` linkado a este
      # payment (via variables.payment_id), reusa.
      existing = Document.active.where(account_id: @account.id, patient_id: @patient.id,
                                       document_type: 'orcamento')
                                 .where("variables->>'portal_payment_id' = ?", @payment.id.to_s)
                                 .first
      return existing if existing

      Document.create!(
        account_id:    @account.id,
        patient_id:    @patient.id,
        document_type: 'orcamento', # 'recibo' não existe no enum core; usamos 'orcamento'
        status:        'enviado',
        is_generated:  true,
        title:         "Recibo · #{format_currency(@installment.amount_cents)} · parcela #{@installment.number}/#{@installment.total_in_series}",
        version:       1,
        variables: {
          portal_payment_id: @payment.id,
          installment_id:    @installment.id,
          amount_cents:      @installment.amount_cents,
          method:            @payment.method,
          paid_at:           (@payment.paid_at || Time.current).iso8601
        }
      )
    end

    def notify!(document)
      PatientPortal::NotificationDispatcher.dispatch(
        account: @account, patient: @patient,
        kind:    'financial_charge',
        title:   'Pagamento confirmado',
        body:    "Sua parcela de #{format_currency(@installment.amount_cents)} foi paga. Toque para ver o recibo.",
        payload: { document_id: document.id, installment_id: @installment.id, payment_id: @payment.id }
      )
    end

    def format_currency(cents)
      "R$ #{format('%.2f', (cents || 0) / 100.0).tr('.', ',')}"
    end
  end
end
