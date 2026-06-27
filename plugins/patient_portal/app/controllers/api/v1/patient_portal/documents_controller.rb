# Documentos visíveis ao paciente. Lista + detalhe + download (streaming via
# JWT — não usa SecureBlobsController do core porque aquele exige Devise).
class Api::V1::PatientPortal::DocumentsController < Api::V1::PatientPortal::BaseController
  before_action :load_document, only: [:show, :download]

  def index
    vis = PatientPortal::DocumentVisibility.new(patient: current_patient, account: current_account)
    render json: { data: vis.all.map { |d| serialize(d) } }
  end

  def show
    render json: { data: serialize(@document, detailed: true) }
  end

  # GET /api/v1/patient_portal/documents/:id/download
  # Streama o arquivo direto pro paciente. Token JWT já valida tenant + acesso.
  # Para PDFs no MVP é OK; quando o portal for ganhar arquivos grandes, vale
  # migrar para signed URL S3 com TTL curto.
  def download
    return render_not_found('Arquivo não disponível.') unless @document.file.attached?

    log!('view', @document)

    send_data @document.file.download,
              filename:    @document.file_name.presence || "documento-#{@document.id}.pdf",
              type:        @document.mime_type.presence || 'application/pdf',
              disposition: 'inline'
  end

  private

  def load_document
    vis = PatientPortal::DocumentVisibility.new(patient: current_patient, account: current_account)
    @document = vis.find(params[:id])
  end

  def serialize(d, detailed: false)
    {
      id:            d.id,
      title:         d.title,
      document_type: d.document_type,
      status:        d.status,
      created_at:    d.created_at,
      signed_at:     d.signed_at,
      sent_at:       d.sent_at,
      file_name:     d.file_name,
      mime_type:     d.mime_type,
      file_size:     d.file_size,
      version:       d.version,
      download_path: "/api/v1/patient_portal/documents/#{d.id}/download",
      generated_by:  detailed && d.generated_by ? { id: d.generated_by.id, name: d.generated_by.name } : nil
    }
  end

  def log!(action, document)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: document,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { document_id: document.id, document_type: document.document_type }
    )
  end
end
