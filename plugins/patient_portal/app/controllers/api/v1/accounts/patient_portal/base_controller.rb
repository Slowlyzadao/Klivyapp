# Base dos endpoints administrativos do portal (consumidos pelo painel da clínica).
# Herda de Api::V1::Accounts::BaseController, que valida sessão Devise + account_id.
class Api::V1::Accounts::PatientPortal::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_admin!

  private

  # RBAC Klivy (BeclinicPermissible) — o ÚNICO sistema de permissões. O painel
  # admin do portal (convites, settings/presets, suspensões) é gerência de
  # pacientes, então gateia por `patients.edit`. super_admin/admin sempre
  # passam (passos 1-2 do BeclinicPermissible); não usar `administrator?` legado.
  def ensure_admin!
    return if Current.user&.beclinic_can?(Current.account, 'patients', 'edit')

    render json: { errors: [{ code: 'forbidden', message: 'Acesso restrito a administradores da clínica.' }] },
           status: :forbidden
  end
end
