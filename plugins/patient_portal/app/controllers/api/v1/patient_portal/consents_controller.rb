# Aceite/revogação de termos Klivy pelo paciente (PRD §11).
# Sprint B entrega apenas portal_terms + lgpd; consentimentos clínicos por
# procedimento (ConsentRecord do plugin Pacientes) vêm na Sprint D.
class Api::V1::PatientPortal::ConsentsController < Api::V1::PatientPortal::BaseController
  # POST /api/v1/patient_portal/consents/portal_terms/accept
  def accept_portal_terms
    accept_term('portal_terms')
  end

  # POST /api/v1/patient_portal/consents/lgpd/accept
  def accept_lgpd
    accept_term('lgpd')
  end

  private

  def accept_term(term_type)
    consent = PatientPortalConsent.accept!(
      account:    current_account,
      patient:    current_patient,
      term_type:  term_type,
      ip:         request.remote_ip,
      user_agent: request.user_agent
    )

    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: 'sign', resource: consent,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { term_type: term_type, term_version: PatientPortalConsent::CURRENT_TERM_VERSION }
    )

    render json: { data: { accepted: true, term_type: term_type, term_version: consent.term_version, accepted_at: consent.accepted_at } }
  end
end
