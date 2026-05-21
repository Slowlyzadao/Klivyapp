# Convite manual de pacientes pelo painel da clínica (PRD §5.6, variante A.1.b).
# Auto-convite (A.1.a) é disparado pelo modelo Patient via callback que checa
# `auto_invite_on_create` em PatientPortalSetting — implementação na Sprint B.
class Api::V1::Accounts::PatientPortal::InvitesController < Api::V1::Accounts::PatientPortal::BaseController
  def index
    invites = Current.account.portal_invites
                     .where(patient_id: params[:patient_id])
                     .order(created_at: :desc)
                     .limit(50)
    render json: { data: invites.map { |i| serialize(i) } }
  end

  def create
    patient = Current.account.patients.find(params[:patient_id])

    invite = Current.account.portal_invites.create!(
      patient:           patient,
      invited_by_user_id: Current.user.id,
      channel:           params[:channel].presence || 'email'
    )

    PatientPortalAccessLog.log!(
      account: Current.account, patient: patient,
      action: 'invite_sent', resource: invite,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { channel: invite.channel }
    )

    # TODO Sprint B: enfileirar SendInviteJob (entrega via WhatsApp/email).
    render json: { data: serialize(invite) }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { errors: [{ code: 'not_found', message: 'Paciente não encontrado.' }] }, status: :not_found
  end

  def destroy
    invite = Current.account.portal_invites.find(params[:id])
    invite.update!(expires_at: Time.current)
    render json: { data: serialize(invite) }
  end

  private

  def serialize(invite)
    {
      id:           invite.id,
      patient_id:   invite.patient_id,
      channel:      invite.channel,
      sent_at:      invite.sent_at,
      accepted_at:  invite.accepted_at,
      expires_at:   invite.expires_at,
      created_at:   invite.created_at,
      status:       invite.accepted_at ? 'accepted' : (invite.expired? ? 'expired' : 'pending')
    }
  end
end
