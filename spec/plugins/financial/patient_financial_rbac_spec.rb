require 'rails_helper'

# RBAC da aba Financeira do paciente — contrato de autorização dos endpoints
# v2 EXCLUSIVOS da aba do prontuário (CHANGELOG 1.8.0.43):
#
#   GET financial/v2/patients/:id/summary   → PatientSummariesController#show
#   GET financial/v2/patients/:id/timeline  → PatientTimelinesController#show
#
# Ambos ganharam `before_action :ensure_view_patient_financial!`, que checa
# `beclinic_can?(:patients, :view_financial)`. Antes eram fail-open (qualquer
# usuário da conta lia o financeiro de qualquer paciente direto pela API).
#
# Contrato travado aqui:
#   - admin nativo da conta                  → 200 (bypass do beclinic_can?)
#   - role COM patients.view_financial       → 200
#   - role SEM patients.view_financial       → 403, MESMO com financial.* completo
#     (financial.* gateia o módulo standalone, não o financeiro de um paciente)
#   - agente sem KlivyRole                    → 403
RSpec.describe 'RBAC: aba Financeira do paciente (Financial v2)', type: :request do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }

  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  let(:summary_path) do
    "/api/v1/accounts/#{account.id}/financial/v2/patients/#{patient.id}/summary"
  end
  let(:timeline_path) do
    "/api/v1/accounts/#{account.id}/financial/v2/patients/#{patient.id}/timeline"
  end

  # Cria uma KlivyRole com `perms` e atribui ao account_user do usuário.
  # Mesmo padrão dos specs de policy do internal_chat.
  def grant!(user, perms)
    role = KlivyRole.create!(
      account: account, name: "test-#{SecureRandom.hex(4)}", permissions: perms
    )
    account.account_users.find_by(user: user).update!(klivy_role: role)
  end

  shared_examples 'gate patients.view_financial' do |path_method|
    let(:path) { send(path_method) }

    it 'permite admin nativo da conta (bypass)' do
      get path, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'permite role COM patients.view_financial' do
      grant!(agent, 'patients' => { 'view_financial' => true })
      get path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'bloqueia (403) role SEM patients.view_financial, ainda que tenha financial.* completo' do
      grant!(agent, 'financial' => {
               'view_dashboard' => true, 'view_receivables' => true,
               'view_cashflow' => true, 'create_transaction' => true
             })
      get path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('forbidden')
    end

    it 'bloqueia (403) agente sem KlivyRole atribuída' do
      get path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET financial/v2/patients/:id/summary' do
    include_examples 'gate patients.view_financial', :summary_path
  end

  describe 'GET financial/v2/patients/:id/timeline' do
    include_examples 'gate patients.view_financial', :timeline_path
  end
end
