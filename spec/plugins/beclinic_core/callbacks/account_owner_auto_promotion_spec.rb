require 'rails_helper'

RSpec.describe 'Account auto-promotion to Owner (BeClinicCore callback)' do
  describe 'AccountBuilder flow (plan purchase)' do
    it 'promotes the first user to Owner after the account is created' do
      user, account = AccountBuilder.new(
        account_name: 'Clínica Teste',
        email: "buyer+#{SecureRandom.hex(4)}@example.com",
        user_full_name: 'Dono da Clínica',
        user_password: 'Password1!',
        confirmed: true
      ).perform

      owner_team = account.teams.find_by(name: 'owner')
      expect(owner_team).to be_present
      expect(owner_team.beclinic_role).to eq('dono')
      expect(owner_team.members).to include(user)
      expect(user.reload.beclinic_role_for(account)).to eq('dono')
    end

    it 'does not promote the user to SuperAdmin type' do
      user, _account = AccountBuilder.new(
        account_name: 'Outra Clínica',
        email: "other+#{SecureRandom.hex(4)}@example.com",
        user_full_name: 'Usuário Teste',
        user_password: 'Password1!',
        confirmed: true
      ).perform

      expect(user.reload.type).to be_nil
      expect(user).not_to be_a(SuperAdmin)
    end
  end

  describe 'Account created in isolation (no user linked)' do
    it 'does not raise — the callback is a no-op when there is no account_user' do
      expect { create(:account) }.not_to raise_error
    end

    it 'does not create an owner team when no user is linked' do
      account = create(:account)
      expect(account.teams.where(name: 'owner')).to be_empty
    end
  end

  describe 'When the first user of the account is a SaaS SuperAdmin' do
    it 'does not create an owner team (SuperAdmins already have full bypass)' do
      super_admin_user = create(:super_admin)
      account = create(:account)
      create(:account_user, account: account, user: super_admin_user)

      # Re-trigger the callback by creating a fresh account and assigning only the super_admin
      # (AccountBuilder is bypassed here because we just want to exercise the callback path)
      fresh_account = Account.create!(name: 'SaaS admin account')
      create(:account_user, account: fresh_account, user: super_admin_user)
      # callback already ran on create! above — the account had no users at that moment,
      # so it was a no-op. The SuperAdmin-check path is verified by the service spec.
      # Here we assert that even if the callback fires when first user IS SuperAdmin,
      # no owner team is created.
      fresh_account.setup_beclinic_owner

      expect(fresh_account.teams.where(name: 'owner')).to be_empty
    end
  end

  describe 'Callback resilience' do
    it 'does not break account creation if the promotion service raises' do
      allow(BeclinicCore::AccountSetup).to receive(:promote_to_owner!).and_raise(StandardError, 'boom')

      expect do
        AccountBuilder.new(
          account_name: 'Clínica Com Erro',
          email: "fail+#{SecureRandom.hex(4)}@example.com",
          user_full_name: 'Falho',
          user_password: 'Password1!',
          confirmed: true
        ).perform
      end.not_to raise_error
    end
  end
end
