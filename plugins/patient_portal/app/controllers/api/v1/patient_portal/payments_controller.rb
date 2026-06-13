# Pagamento online iniciado pelo paciente (PRD §9, Sprint F).
#
# Endpoints:
#   POST /payments                 → cria PortalPayment + chama gateway
#   GET  /payments/:id             → consulta status (front faz polling)
#   POST /payments/:id/cancel      → paciente desiste
#   POST /payments/:id/simulate_paid → DEV ONLY (gateway=mock) — marca pago
#
# Em produção, status=paid vem do webhook do gateway (já existente para Asaas).
class Api::V1::PatientPortal::PaymentsController < Api::V1::PatientPortal::BaseController
  before_action :load_payment, only: [:show, :cancel, :simulate_paid]

  def create
    inst = Financial::Installment.where(account_id: current_account.id,
                                         patient_id: current_patient.id).find(params[:installment_id])

    return render_error('Esta parcela já foi paga.') if inst.status == 'recebido'
    return render_error('Esta parcela foi cancelada.') if %w[cancelado estornado].include?(inst.status)

    method = params[:method].to_s
    return render_error('Método inválido.') unless PortalPayment::METHODS.include?(method)

    gateway = PatientPortal::Payment::Gateway.for(account: current_account)

    payment = PortalPayment.create!(
      account:      current_account,
      patient:      current_patient,
      installment:  inst,
      method:       method,
      gateway:      gateway.is_a?(PatientPortal::Payment::MockGateway) ? 'mock' : 'asaas',
      amount_cents: inst.amount_cents,
      status:       'pending'
    )

    begin
      result = gateway.create_charge!(method: method, amount_cents: inst.amount_cents,
                                      patient: current_patient, installment: inst)
      payment.update!(result.to_attrs.merge(status: 'awaiting_payment'))
    rescue StandardError => e
      payment.update!(status: 'failed', gateway_payload: { error: e.message })
      Rails.logger.error("[Payments#create] gateway falhou: #{e.message}")
      return render_error('Não foi possível iniciar o pagamento. Tente novamente.')
    end

    log!('create', payment)
    render json: { data: serialize(payment) }, status: :created
  end

  def show
    render json: { data: serialize(@payment) }
  end

  def cancel
    return render_error('Este pagamento não pode mais ser cancelado.') unless @payment.cancellable?

    @payment.mark_cancelled!
    log!('cancel', @payment)
    render json: { data: serialize(@payment) }
  end

  # POST /payments/:id/simulate_paid — DEV ONLY.
  # Em produção, status vem do webhook do gateway; este endpoint retorna 403.
  def simulate_paid
    return render_error('Indisponível em produção.', status: :forbidden) if Rails.env.production?
    return render_error('Apenas pagamentos do mock gateway aceitam simulação.') unless @payment.gateway == 'mock'
    return render_error('Pagamento não está aguardando confirmação.') unless @payment.awaiting_payment?

    @payment.mark_paid!(at: Time.current, payload: { simulated_at: Time.current.iso8601 })
    PatientPortal::PaymentReceiptIssuer.new(payment: @payment.reload).call

    log!('simulate_paid', @payment)
    render json: { data: serialize(@payment.reload) }
  end

  private

  def load_payment
    @payment = PortalPayment.where(account_id: current_account.id,
                                    patient_id: current_patient.id).find(params[:id])
  end

  def serialize(p)
    {
      id:                 p.id,
      installment_id:     p.financial_installment_id,
      method:             p.method,
      status:             p.status,
      gateway:            p.gateway,
      amount_cents:       p.amount_cents,
      pix_qr_code:        p.pix_qr_code,
      pix_copy_paste:     p.pix_copy_paste,
      boleto_url:         p.boleto_url,
      boleto_barcode:     p.boleto_barcode,
      expires_at:         p.expires_at,
      paid_at:            p.paid_at,
      can_simulate:       Rails.env.development? && p.gateway == 'mock' && p.awaiting_payment?
    }
  end

  def log!(action, resource)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: resource,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { payment_id: resource.id, status: resource.status }
    )
  end
end
