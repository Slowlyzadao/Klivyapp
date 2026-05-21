# Base dos endpoints administrativos do portal (consumidos pelo painel da clínica).
# Herda de Api::V1::Accounts::BaseController, que valida sessão Devise + account_id.
class Api::V1::Accounts::PatientPortal::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  private

  def ensure_admin!
    return if Current.user&.administrator?

    render json: { errors: [{ code: 'forbidden', message: 'Acesso restrito a administradores da clínica.' }] },
           status: :forbidden
  end
end
