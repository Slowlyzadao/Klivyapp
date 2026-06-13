# Base controller das APIs consumidas pelo SPA do paciente.
#
# Autenticação JWT (sem Devise). `current_patient` e `current_account` ficam
# disponíveis para os controllers filhos. Todas as queries DEVEM escopar por
# `current_account` (princípio de least privilege — PRD §17.1).
class Api::V1::PatientPortal::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_patient!

  # current_patient — paciente "ativo" (target dos dados; pode ser self ou
  # dependente). Sprint I separou de `current_acting_patient` (quem logou).
  # Controllers existentes seguem usando current_patient sem modificação.
  attr_reader :current_patient, :current_account, :current_session, :current_acting_patient

  rescue_from PatientPortal::JwtEncoder::InvalidTokenError, with: :render_unauthorized
  rescue_from ActiveRecord::RecordNotFound,                 with: :render_not_found
  rescue_from PatientPortal::Authenticator::FloodError,     with: :render_too_many_requests
  rescue_from PatientPortal::Authenticator::InvalidOtpError, with: :render_unauthorized
  rescue_from PatientPortal::Authenticator::NoContactError,  with: :render_not_found

  private

  def authenticate_patient!
    token = bearer_token
    return render_unauthorized('Token ausente.') if token.blank?

    payload = PatientPortal::JwtEncoder.decode(token)
    session = PatientPortalSession.find_by(jwt_jti: payload[:jti])

    return render_unauthorized('Sessão inválida.') if session.blank? || !session.valid_session?

    # Sprint I — Resolução dual: acting = quem logou, active = quem está sendo
    # acessado agora (self ou dependente). Para sessões antigas migradas, ambos
    # apontam pro mesmo patient.
    acting = Patient.find_by(id: payload[:sub], account_id: payload[:account_id])
    return render_unauthorized('Paciente não encontrado.') unless acting&.portal_active?

    active = Patient.find_by(id: session.active_patient_id, account_id: payload[:account_id])
    active ||= acting

    # Defesa: se active_patient_id virou inválido (revogado, etc), volta pro self.
    if active.id != acting.id
      ctx = PatientPortal::SessionContext.new(session: session)
      unless ctx.can_act_on?(active)
        session.update!(active_patient_id: acting.id)
        active = acting
      end
    end

    @current_session         = session
    @current_acting_patient  = acting
    @current_patient         = active
    @current_account         = acting.account

    session.touch_last_seen!(ip: request.remote_ip, user_agent: request.user_agent)
  end

  def bearer_token
    auth = request.headers['Authorization'].to_s
    auth.sub(/^Bearer\s+/i, '').strip.presence
  end

  def render_unauthorized(message = 'Não autorizado.')
    render json: { errors: [{ code: 'unauthorized', message: message }] }, status: :unauthorized
  end

  def render_not_found(exception = nil)
    # Não vaza message de ActiveRecord::RecordNotFound (que carrega SQL completo).
    # Mantém custom messages quando o controller chama explicitamente.
    msg = if exception.is_a?(ActiveRecord::RecordNotFound)
            'Recurso não encontrado.'
          elsif exception.is_a?(StandardError)
            exception.message
          else
            exception.presence || 'Recurso não encontrado.'
          end
    render json: { errors: [{ code: 'not_found', message: msg }] }, status: :not_found
  end

  def render_too_many_requests(exception)
    render json: { errors: [{ code: 'too_many_requests', message: exception.message }] }, status: :too_many_requests
  end

  def render_error(message, status: :unprocessable_entity, code: 'invalid')
    render json: { errors: [{ code: code, message: message }] }, status: status
  end
end
