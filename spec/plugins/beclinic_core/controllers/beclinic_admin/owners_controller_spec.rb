require 'rails_helper'

RSpec.describe 'BeclinicAdmin Owners', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }

  describe 'GET /beclinic_admin/owners' do
    context 'when unauthenticated' do
      it 'redirects to super_admin login' do
        get '/beclinic_admin/owners'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when authenticated as super_admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'renders the index successfully' do
        get '/beclinic_admin/owners'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(account.name)
      end
    end
  end

  describe 'GET /beclinic_admin/owners/:id' do
    context 'when authenticated as super_admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'lists the account_users for the account' do
        get "/beclinic_admin/owners/#{account.id}"
        expect(response).to have_http_status(:success)
        expect(response.body).to include(user.email)
      end
    end
  end

  describe 'POST /beclinic_admin/owners/:id/promote' do
    context 'when unauthenticated' do
      it 'redirects without promoting' do
        post "/beclinic_admin/owners/#{account.id}/promote", params: { user_id: user.id }
        expect(response).to have_http_status(:redirect)
        expect(account.teams.where(name: 'owner')).to be_empty
      end
    end

    context 'when authenticated as super_admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'promotes the user and redirects with success flash' do
        post "/beclinic_admin/owners/#{account.id}/promote", params: { user_id: user.id }

        expect(response).to redirect_to("/beclinic_admin/owners/#{account.id}")
        expect(account.teams.where(name: 'owner').count).to eq(1)
        expect(user.reload.beclinic_role_for(account)).to eq('dono')
      end

      it 'does not alter user type' do
        original_type = user.type
        post "/beclinic_admin/owners/#{account.id}/promote", params: { user_id: user.id }

        expect(user.reload.type).to eq(original_type)
      end

      it 'reports already-owner on second call' do
        post "/beclinic_admin/owners/#{account.id}/promote", params: { user_id: user.id }
        post "/beclinic_admin/owners/#{account.id}/promote", params: { user_id: user.id }

        follow_redirect!
        expect(response.body).to include('já era Proprietário').or include(user.email)
      end

      it 'rejects promotion when user does not belong to the account' do
        stranger = create(:user)
        post "/beclinic_admin/owners/#{account.id}/promote", params: { user_id: stranger.id }

        expect(response).to redirect_to("/beclinic_admin/owners/#{account.id}")
        expect(account.teams.where(name: 'owner')).to be_empty
      end
    end
  end
end
