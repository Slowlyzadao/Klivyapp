# Endpoint consultivo: "posso agendar agora?". Front decide se mostra avisos
# ou libera o botão. Não bloqueia nada por si — segurança real fica nas regras
# dos endpoints de criação (PRD §7.3).
class Api::V1::PatientPortal::PreflightController < Api::V1::PatientPortal::BaseController
  def appointment
    result = PatientPortal::PreflightChecker.new(
      patient: current_patient, account: current_account
    ).call

    render json: { data: result.to_h }
  end
end
