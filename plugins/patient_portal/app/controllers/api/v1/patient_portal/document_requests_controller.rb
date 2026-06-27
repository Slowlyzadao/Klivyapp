# Pedidos de documento (2ª via ou tipo genérico) feitos pelo paciente.
class Api::V1::PatientPortal::DocumentRequestsController < Api::V1::PatientPortal::BaseController
  def index
    list = PortalDocumentRequest.for_patient(current_patient.id)
                                .where(account_id: current_account.id)
                                .recent_first
                                .limit(20)
    render json: { data: list.map { |r| serialize(r) } }
  end

  def create
    # source_document_id (se enviado) precisa pertencer ao paciente — caso
    # contrário paciente vazaria a existência de doc de outro paciente.
    source_id = params[:source_document_id].presence
    if source_id
      owned = Document.where(account_id: current_account.id,
                              patient_id: current_patient.id,
                              id: source_id).exists?
      return render_not_found('Documento de origem não encontrado.') unless owned
    end

    record = PortalDocumentRequest.new(
      account:            current_account,
      patient:            current_patient,
      source_document_id: source_id,
      document_type:      params[:document_type].presence,
      reason:             params[:reason].to_s.strip,
      status:             'pending'
    )

    if record.save
      log!('create', record)
      render json: { data: serialize(record) }, status: :created
    else
      render_error(record.errors.full_messages.join('; '))
    end
  end

  def destroy
    record = PortalDocumentRequest.where(account_id: current_account.id,
                                          patient_id: current_patient.id).find(params[:id])
    return render_error('Pedido não pode mais ser cancelado.') unless record.cancelable_by_patient?

    record.update!(status: 'cancelled', processed_at: Time.current,
                   processed_notes: params[:reason].to_s.strip.presence)
    log!('cancel', record)
    render json: { data: serialize(record) }
  end

  private

  def serialize(r)
    {
      id:                  r.id,
      status:              r.status,
      created_at:          r.created_at,
      document_type:       r.document_type,
      reason:              r.reason,
      source_document:     r.source_document ? { id: r.source_document.id, title: r.source_document.title, document_type: r.source_document.document_type } : nil,
      fulfilled_document:  r.fulfilled_document ? { id: r.fulfilled_document.id, title: r.fulfilled_document.title, download_path: "/api/v1/patient_portal/documents/#{r.fulfilled_document.id}/download" } : nil,
      processed_at:        r.processed_at,
      processed_notes:     r.processed_notes
    }
  end

  def log!(action, record)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: record,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { status: record.status, document_type: record.document_type }
    )
  end
end
