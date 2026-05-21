# Gerencia subscriptions de Web Push do paciente (Sprint G).
#
# Endpoints:
#   GET    /api/v1/patient_portal/push_subscriptions/public_key
#     → entrega VAPID public key pra `pushManager.subscribe()` no front.
#   POST   /api/v1/patient_portal/push_subscriptions
#     → cria/atualiza subscription (idempotente via endpoint unique).
#   DELETE /api/v1/patient_portal/push_subscriptions
#     → remove subscription (paciente desativou push no device).
class Api::V1::PatientPortal::PushSubscriptionsController < Api::V1::PatientPortal::BaseController
  # Todas as rotas exigem paciente logado — só inscreve push após login.

  def public_key
    render json: { data: { public_key: VapidKeys.public_key } }
  end

  def create
    endpoint   = params.dig(:subscription, :endpoint) || params[:endpoint]
    p256dh     = params.dig(:subscription, :keys, :p256dh) || params[:p256dh]
    auth       = params.dig(:subscription, :keys, :auth)   || params[:auth]

    return render_error('Subscription incompleta.') if endpoint.blank? || p256dh.blank? || auth.blank?

    sub = PatientPortalPushSubscription.find_or_initialize_by(endpoint: endpoint)
    sub.assign_attributes(
      account_id:    current_account.id,
      patient_id:    current_patient.id,
      p256dh_key:    p256dh,
      auth_key:      auth,
      user_agent:    request.user_agent.to_s.first(500),
      disabled_at:   nil,
      failure_count: 0,
      last_used_at:  Time.current
    )
    sub.save!

    log!('push_subscribe', sub)
    render json: { data: serialize(sub) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: [{ code: 'invalid', message: e.message }] }, status: :unprocessable_entity
  end

  def destroy
    endpoint = params[:endpoint] || params.dig(:subscription, :endpoint)
    return render_error('Endpoint obrigatório.') if endpoint.blank?

    sub = PatientPortalPushSubscription.find_by(
      patient_id: current_patient.id, endpoint: endpoint
    )
    sub&.destroy
    log!('push_unsubscribe', sub) if sub
    head :no_content
  end

  private

  def serialize(sub)
    { id: sub.id, endpoint: sub.endpoint, created_at: sub.created_at, last_used_at: sub.last_used_at }
  end

  def log!(action, resource)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: resource,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { endpoint: resource&.endpoint.to_s.first(120) }
    )
  end
end
