# Endpoints públicos de auth (não exigem JWT pré-existente).
# Toda lógica de negócio fica em PatientPortal::Authenticator — controller magro.
class Api::V1::PatientPortal::AuthController < ActionController::API
  rescue_from PatientPortal::Authenticator::FloodError,     with: :render_too_many_requests
  rescue_from PatientPortal::Authenticator::InvalidOtpError, with: :render_unauthorized
  rescue_from PatientPortal::Authenticator::NoContactError,  with: :render_not_found
  rescue_from PatientPortal::OtpDispatcher::WhatsappNotEnabledError, with: :render_bad_request

  # POST /api/v1/patient_portal/auth/request_otp
  def request_otp
    result = PatientPortal::Authenticator.request_otp(
      identifier_raw: params[:identifier],
      channel:        params[:channel] || 'email',
      ip:             request.remote_ip
    )
    render json: { data: result }
  end

  # POST /api/v1/patient_portal/auth/verify_otp
  def verify_otp
    result = PatientPortal::Authenticator.verify_otp(
      identifier_raw: params[:identifier],
      code:           params[:code],
      ip:             request.remote_ip
    )
    render json: { data: result }
  end

  # POST /api/v1/patient_portal/auth/select_account
  def select_account
    # Verifica o temp_token para garantir que o paciente passou por verify_otp
    payload = PatientPortal::JwtEncoder.decode(params[:temp_token])
    raise PatientPortal::Authenticator::NoContactError, 'Token temporário expirado.' unless payload[:exp].to_i > Time.current.to_i

    # account_id no temp_token é null — paciente escolhe agora.
    selected_account_id = params[:account_id].to_i
    raise PatientPortal::Authenticator::NoContactError, 'account_id ausente.' if selected_account_id.zero?

    result = PatientPortal::Authenticator.select_account(
      patient_id: payload[:sub],
      account_id: selected_account_id,
      ip:         request.remote_ip,
      user_agent: request.user_agent
    )

    render json: {
      data: {
        jwt:        result[:jwt],
        expires_at: result[:expires_at],
        patient: serialize_patient(result[:patient]),
        account: { id: result[:patient].account.id, name: result[:patient].account.name }
      }
    }
  rescue PatientPortal::JwtEncoder::InvalidTokenError => e
    render_unauthorized(e)
  end

  # DELETE /api/v1/patient_portal/auth/logout
  def logout
    # Faz parse manual do header pra revogar sem chamar o BaseController (que dá 401 se já estiver expirado)
    token = request.headers['Authorization'].to_s.sub(/^Bearer\s+/i, '').strip
    return render(json: { data: { logged_out: true } }) if token.blank?

    payload = PatientPortal::JwtEncoder.decode(token) rescue nil
    PatientPortalSession.where(jwt_jti: payload&.[](:jti)).update_all(revoked_at: Time.current) if payload

    render json: { data: { logged_out: true } }
  end

  # GET /api/v1/patient_portal/auth/me
  # Apenas retorna o paciente da sessão atual (requer JWT válido).
  def me
    # Mini-mixin de autenticação inline pra esse endpoint específico
    token = request.headers['Authorization'].to_s.sub(/^Bearer\s+/i, '').strip
    return render_unauthorized('Token ausente.') if token.blank?

    payload = PatientPortal::JwtEncoder.decode(token)
    session = PatientPortalSession.find_by(jwt_jti: payload[:jti])
    return render_unauthorized('Sessão inválida.') unless session&.valid_session?

    patient = Patient.find_by(id: payload[:sub], account_id: payload[:account_id])
    return render_unauthorized('Paciente não encontrado.') unless patient&.portal_active?

    render json: {
      data: {
        patient: serialize_patient(patient),
        account: { id: patient.account.id, name: patient.account.name },
        session: { expires_at: session.expires_at },
        consent: {
          # PRD §11.1: termo Klivy obrigatório no primeiro acesso. Modal bloqueia
          # navegação até o paciente aceitar a versão vigente.
          required: !patient_accepted_current_portal_terms?(patient),
          term_version: PatientPortalConsent::CURRENT_TERM_VERSION
        }
      }
    }
  rescue PatientPortal::JwtEncoder::InvalidTokenError => e
    render_unauthorized(e.message)
  end

  private

  def patient_accepted_current_portal_terms?(patient)
    PatientPortalConsent
      .where(patient_id: patient.id, term_type: 'portal_terms')
      .where(term_version: PatientPortalConsent::CURRENT_TERM_VERSION)
      .where(revoked_at: nil)
      .exists?
  end

  # Centraliza serialização do Patient. Prioriza campos clínicos (Patient.*) e
  # cai em Contact.* como fallback — alinhado com PatientPortal::PatientFinder.
  def serialize_patient(patient)
    {
      id:    patient.id,
      name:  patient.name,
      email: patient.email.presence || patient.contact&.email,
      phone: patient.try(:phone).presence || patient.contact&.phone_number
    }
  end

  def render_unauthorized(message)
    msg = message.is_a?(StandardError) ? message.message : message.to_s
    render json: { errors: [{ code: 'unauthorized', message: msg }] }, status: :unauthorized
  end

  def render_not_found(exception)
    render json: { errors: [{ code: 'not_found', message: exception.message }] }, status: :not_found
  end

  def render_too_many_requests(exception)
    render json: { errors: [{ code: 'too_many_requests', message: exception.message }] }, status: :too_many_requests
  end

  def render_bad_request(exception)
    render json: { errors: [{ code: 'bad_request', message: exception.message }] }, status: :bad_request
  end
end
