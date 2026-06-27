# frozen_string_literal: true

# Endpoint público para assinatura remota de uma SessionLog pelo paciente.
# Acesso é exclusivamente via `remote_token` único gerado em
# `SessionLog#send_patient_remote_signature_link!`. Sem autenticação de usuário —
# o token é a credencial.
#
#   GET    /public/api/v1/session_log_signatures/:remote_token
#     => devolve metadados mínimos (paciente, procedimento, data, expiração).
#
#   PATCH  /public/api/v1/session_log_signatures/:remote_token
#     body: { signature: 'data:image/webp;base64,...', device_info? }
#     => grava a assinatura.
class Public::Api::V1::SessionLogSignaturesController < ActionController::API
  before_action :load_session_log

  def show
    render json: {
      patient_name: @session_log.patient&.name,
      procedure_name: @session_log.procedure_name.presence || @session_log.treatment_item&.procedure_name,
      performed_at: @session_log.performed_at&.iso8601,
      expires_at: @session_log.patient_signature_remote_link_expires_at&.iso8601,
      already_signed: @session_log.patient_signed?
    }
  end

  def update
    if @session_log.patient_signed?
      render json: { error: 'Esta sessão já foi assinada.' }, status: :unprocessable_entity
      return
    end

    if @session_log.patient_signature_remote_link_expired?
      render json: { error: 'O link de assinatura expirou.' }, status: :gone
      return
    end

    result = ::Patients::SessionLogPatientSigner.call(
      session_log: @session_log,
      mode: 'remote_link',
      signature_blob: params[:signature],
      ip_address: request.remote_ip,
      device_info: params[:device_info] || request.user_agent,
      actor: nil
    )

    if result.success?
      render json: { success: true, signed_at: result.session_log.patient_signed_at.iso8601 }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def load_session_log
    token = params[:remote_token].to_s
    return render json: { error: 'Token ausente.' }, status: :bad_request if token.blank?

    @session_log = SessionLog.active.find_by(patient_signature_remote_token: token)

    if @session_log.nil?
      render json: { error: 'Token inválido ou já utilizado.' }, status: :not_found
    elsif @session_log.patient_signature_remote_link_expired?
      render json: { error: 'O link de assinatura expirou.' }, status: :gone
    end
  end
end
