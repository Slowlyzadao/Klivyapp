# Consentimentos clínicos (ConsentRecord) — PRD §11.
#
# Diferente do `consents_controller.rb` (que trata portal_terms + lgpd, gates
# do portal). Aqui é o termo clínico por procedimento, com assinatura remota.
class Api::V1::PatientPortal::ConsentRecordsController < Api::V1::PatientPortal::BaseController
  before_action :load_consent, only: [:show, :sign]

  def index
    vis = PatientPortal::ConsentRecordVisibility.new(patient: current_patient, account: current_account)
    render json: {
      data: {
        pending: vis.pending.map { |c| serialize(c) },
        signed:  vis.signed.map  { |c| serialize(c) }
      }
    }
  end

  def show
    render json: { data: serialize(@consent, detailed: true) }
  end

  # POST /api/v1/patient_portal/consent_records/:id/sign
  # Body: { signature_blob: "data:image/png;base64,..." }
  #
  # Aplica assinatura remota direto via JWT. Não usa o `remote_token` clássico
  # do core (que viaja por link em e-mail/SMS) — o paciente já está autenticado
  # no portal, o que é equivalente do ponto de vista de identidade.
  def sign
    return render_error('Este termo já foi assinado.') if @consent.signed?
    return render_error('Este termo já está vencido.', code: 'expired') if @consent.expired?

    blob = params[:signature_blob].to_s
    return render_error('Assinatura ausente.') if blob.blank?
    return render_error('Assinatura inválida.') unless blob.start_with?('data:image/')

    @consent.sign_remotely!(
      signature_blob: blob,
      ip_address:     request.remote_ip,
      device_info:    request.user_agent
    )

    log!('sign', @consent)
    render json: { data: serialize(@consent, detailed: true) }
  rescue StandardError => e
    render_error(e.message)
  end

  private

  def load_consent
    vis = PatientPortal::ConsentRecordVisibility.new(patient: current_patient, account: current_account)
    @consent = vis.find(params[:id])
  end

  def serialize(c, detailed: false)
    base = {
      id:                c.id,
      title:             c.title,
      status:            c.status,
      mode:              c.mode,
      signature_method:  c.signature_method,
      created_at:        c.created_at,
      signed_at:         c.signed_at,
      expires_at:        c.expires_at,
      can_sign:          c.pending? && !c.expired?
    }
    return base unless detailed

    base.merge(
      body:             c.body,
      observations:     c.observations,
      form_template_id: c.form_template_id
    )
  end

  def log!(action, consent)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: consent,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { consent_id: consent.id, status: consent.status }
    )
  end
end
