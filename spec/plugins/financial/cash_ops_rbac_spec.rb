require 'rails_helper'

# RBAC das OPERAÇÕES DE CAIXA — gate em camadas (decisão 2026-05-30):
#   receber/lançar/editar/reclassificar → RECEPCAO/GERENTE/ADMIN
#   estornar/excluir lançamento         → GERENTE/ADMIN
#   rename/destroy_provider             → ADMIN/GERENTE
#
# Usa ids inexistentes de propósito: o `authorize_*` roda ANTES do `set_*`,
# então não-autorizado = 403 e autorizado cai em 404/422 — nada é mutado.
RSpec.describe 'RBAC: operações de caixa (Financial v2)', type: :request do
  let(:account) { create(:account) }
  let(:base)    { "/api/v1/accounts/#{account.id}/financial/v2" }

  let(:admin)    { create(:user, account: account, role: :administrator) } # ADMIN (bypass nativo)
  let(:gerente)  { with_preset(create(:user, account: account, role: :agent), 'gerente') }
  let(:recepcao) { with_preset(create(:user, account: account, role: :agent), 'recepcionista') }
  let(:sem_caixa) { create(:user, account: account, role: :agent) } # sem KlivyRole

  # Atribui um KlivyRole com preset_key (o gate lê account_user.klivy_role.preset_key).
  # Mesmo padrão do `grant!` do patient_financial_rbac_spec.rb.
  def with_preset(user, preset)
    role = KlivyRole.create!(account: account, name: "test-#{SecureRandom.hex(4)}", preset_key: preset)
    account.account_users.find_by(user: user).update!(klivy_role: role)
    user
  end

  before do
    # isola a RBAC do wizard de setup (senão o 412 do ensure_setup_complete! vem ANTES do gate)
    allow_any_instance_of(Financial::SetupState).to receive(:required_steps_done?).and_return(true)
  end

  def post_as(user, path, params = {})
    post "#{base}#{path}", params: params, headers: user.create_new_auth_token, as: :json
  end

  def delete_as(user, path)
    delete "#{base}#{path}", headers: user.create_new_auth_token, as: :json
  end

  describe 'POST installments/:id/pay — exige RECEPCAO/GERENTE/ADMIN' do
    it 'bloqueia quem não tem papel de caixa (403)' do
      post_as(sem_caixa, '/installments/999999999/pay', payment_method: 'pix')
      expect(response).to have_http_status(:forbidden)
    end

    %i[recepcao gerente admin].each do |role|
      it "deixa #{role} passar (não 403)" do
        post_as(send(role), '/installments/999999999/pay', payment_method: 'pix')
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST installments/:id/refund — exige GERENTE/ADMIN' do
    it 'bloqueia RECEPCAO (403) — PROVA do gate em camadas' do
      post_as(recepcao, '/installments/999999999/refund')
      expect(response).to have_http_status(:forbidden)
    end

    %i[gerente admin].each do |role|
      it "deixa #{role} passar (não 403)" do
        post_as(send(role), '/installments/999999999/refund')
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST payment_methods/rename_provider — exige ADMIN/GERENTE' do
    it 'bloqueia RECEPCAO (403) — era o bug sem gate' do
      post_as(recepcao, '/payment_methods/rename_provider', provider: 'ZZZ', provider_alias: 'x')
      expect(response).to have_http_status(:forbidden)
    end

    it 'deixa GERENTE passar (não 403)' do
      post_as(gerente, '/payment_methods/rename_provider', provider: 'ZZZ', provider_alias: 'x')
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe 'POST entries (lançar) — exige RECEPCAO/GERENTE/ADMIN' do
    it 'bloqueia quem não tem papel de caixa (403)' do
      post_as(sem_caixa, '/entries', entry: { direction: 'in' })
      expect(response).to have_http_status(:forbidden)
    end

    it 'deixa RECEPCAO passar (422 do body inválido, não 403)' do
      post_as(recepcao, '/entries', entry: { direction: 'in' })
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe 'DELETE entries/:id (excluir lançamento) — exige GERENTE/ADMIN' do
    it 'bloqueia RECEPCAO (403)' do
      delete_as(recepcao, '/entries/999999999')
      expect(response).to have_http_status(:forbidden)
    end

    it 'deixa ADMIN passar (404, não 403)' do
      delete_as(admin, '/entries/999999999')
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
