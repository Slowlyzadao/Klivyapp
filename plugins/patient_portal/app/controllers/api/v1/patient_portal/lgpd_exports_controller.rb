# Export de dados pessoais (S6 do anexo + PRD §13.1). MVP entrega JSON
# self-service do que está exposto ao paciente. PDF formatado vem em F2.
#
# Princípio: retorna apenas o que o paciente JÁ VÊ no portal. Dados
# clínicos sensíveis (anamnese completa, prontuário) só aparecem se a
# clínica habilitou no setting.
class Api::V1::PatientPortal::LgpdExportsController < Api::V1::PatientPortal::BaseController
  def create
    payload = build_export_payload
    log!('export', current_patient, metadata: { kind: 'lgpd_data_export' })
    render json: { data: payload }
  end

  private

  def build_export_payload
    appts = PatientPortal::AppointmentVisibility.new(patient: current_patient, account: current_account)
    docs  = PatientPortal::DocumentVisibility.new(patient: current_patient, account: current_account)
    fin   = PatientPortal::FinancialSummary.new(patient: current_patient, account: current_account)
    anam  = PatientPortal::AnamnesisVisibility.new(patient: current_patient, account: current_account)
    consents = PatientPortalConsent.active.where(account_id: current_account.id, patient_id: current_patient.id)

    {
      exported_at: Time.current,
      patient: {
        id: current_patient.id, name: current_patient.name,
        email: current_patient.email, phone: current_patient.phone,
        birthdate: current_patient.birthdate, sex: current_patient.sex
      },
      account: { id: current_account.id, name: current_account.name },
      portal_consents: consents.map { |c| { term_type: c.term_type, term_version: c.term_version, accepted_at: c.accepted_at } },
      appointments: {
        upcoming: appts.upcoming.map { |e| { id: e.id, title: e.title, starts_at: e.starts_at, status: e.status } },
        past:     appts.past.map { |e|     { id: e.id, title: e.title, starts_at: e.starts_at, status: e.status } }
      },
      documents: docs.all.map { |d| { id: d.id, title: d.title, type: d.document_type, created_at: d.created_at } },
      financial: {
        totals: fin.totals,
        installments: fin.installments(scope: :all).map { |i|
          { id: i.id, amount_cents: i.amount_cents, status: i.status, due_date: i.due_date }
        }
      },
      anamneses: anam.exposed? ? anam.all.map { |a| { id: a.id, version: a.version_number, finalized_at: a.finalized_at } } : 'não exposto (default-deny)',
      access_logs_recent: PatientPortalAccessLog.where(account_id: current_account.id, patient_id: current_patient.id)
                                                  .order(created_at: :desc).limit(20)
                                                  .map { |l| { action: l.action, resource_type: l.resource_type, created_at: l.created_at } }
    }
  end

  def log!(action, resource, metadata: {})
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: resource,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: metadata
    )
  end
end
