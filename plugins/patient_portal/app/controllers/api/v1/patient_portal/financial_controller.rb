# Financeiro read-only do paciente (PRD §9). MVP entrega:
#   - GET financial/summary  → totais + próxima parcela
#   - GET financial/installments → lista (open|paid|all, conforme setting)
#   - GET financial/installments/:id → detalhe
#   - GET financial/installments/:id/proof → comprovante (streaming)
class Api::V1::PatientPortal::FinancialController < Api::V1::PatientPortal::BaseController
  before_action :load_installment, only: [:show_installment, :proof]

  # GET /api/v1/patient_portal/financial/summary
  def summary
    svc = PatientPortal::FinancialSummary.new(patient: current_patient, account: current_account)
    nxt = svc.next_due

    render json: {
      data: {
        totals:            svc.totals,
        show_paid_history: svc.show_paid_history?,
        next_due:          nxt ? serialize_installment(nxt) : nil
      }
    }
  end

  # GET /api/v1/patient_portal/financial/installments?scope=open|paid|all
  def index_installments
    svc = PatientPortal::FinancialSummary.new(patient: current_patient, account: current_account)
    scope = params[:scope].to_s.presence&.to_sym || :all
    render json: { data: svc.installments(scope: scope).map { |i| serialize_installment(i) } }
  end

  # GET /api/v1/patient_portal/financial/installments/:id
  def show_installment
    render json: { data: serialize_installment(@installment, detailed: true) }
  end

  # GET /api/v1/patient_portal/financial/installments/:id/proof
  # Streama o comprovante. Só disponível se a parcela foi recebida.
  def proof
    return render_not_found('Comprovante não disponível.') unless @installment.payment_proof.attached?

    log!('view', @installment, metadata: { kind: 'payment_proof' })

    send_data @installment.payment_proof.download,
              filename:    "comprovante-#{@installment.id}.pdf",
              type:        @installment.payment_proof.content_type.presence || 'application/pdf',
              disposition: 'inline'
  end

  private

  def load_installment
    svc = PatientPortal::FinancialSummary.new(patient: current_patient, account: current_account)
    @installment = svc.find(params[:id])
  end

  def serialize_installment(i, detailed: false)
    {
      id:                   i.id,
      number:               i.number,
      total_in_series:      i.total_in_series,
      amount_cents:         i.amount_cents,
      received_amount_cents: i.received_amount_cents,
      remaining_cents:      i.remaining_cents,
      status:               i.status,
      payment_method:       i.payment_method,
      due_date:             i.due_date,
      competence_date:      i.competence_date,
      received_at:          i.received_at,
      has_proof:            i.payment_proof.attached?,
      overdue:              i.overdue?,
      notes:                detailed ? i.notes : nil,
      pix_qr_code:          detailed ? i.pix_qr_code : nil,
      barcode_line:         detailed ? i.barcode_line : nil
    }
  end

  def log!(action, resource, metadata: {})
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: resource,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: metadata.merge(installment_id: resource.id)
    )
  end
end
