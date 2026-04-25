require 'rails_helper'

RSpec.describe BeclinicCore::AccountSetup do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '.promote_to_owner!' do
    context 'with a user that belongs to the account' do
      it 'creates an Owner team with beclinic_role dono' do
        result = described_class.promote_to_owner!(account: account, user: user)

        expect(result.team).to be_present
        expect(result.team.name).to eq('owner')
        expect(result.team.beclinic_role).to eq('dono')
        expect(result.promoted).to be true
      end

      it 'assigns the user as member of the Owner team' do
        result = described_class.promote_to_owner!(account: account, user: user)

        expect(result.team.members).to include(user)
      end

      it 'grants full permissions via beclinic_can? on any action' do
        described_class.promote_to_owner!(account: account, user: user)

        expect(user.beclinic_can?(account, :patients, :delete)).to be true
        expect(user.beclinic_can?(account, :financial, :export_cashflow)).to be true
        expect(user.beclinic_role_for(account)).to eq('dono')
      end

      it 'does not modify the user type (never promotes to SuperAdmin)' do
        original_type = user.type
        described_class.promote_to_owner!(account: account, user: user)

        expect(user.reload.type).to eq(original_type)
      end

      it 'is idempotent — second call returns promoted: false' do
        described_class.promote_to_owner!(account: account, user: user)
        result = described_class.promote_to_owner!(account: account, user: user)

        expect(result.promoted).to be false
        expect(account.teams.where(name: 'owner').count).to eq(1)
      end

      it 'removes the user from other teams in the same account' do
        other_team = create(:team, account: account, name: 'gerente')
        other_team.team_members.create!(user: user)

        described_class.promote_to_owner!(account: account, user: user)

        expect(user.teams.where(account_id: account.id).pluck(:name)).to eq(['owner'])
      end

      it 'does not affect other accounts the user belongs to' do
        other_account = create(:account)
        other_account_team = create(:team, account: other_account, name: 'gerente')
        create(:account_user, user: user, account: other_account)
        other_account_team.team_members.create!(user: user)

        described_class.promote_to_owner!(account: account, user: user)

        expect(user.teams.where(account_id: other_account.id)).to include(other_account_team)
      end
    end

    context 'with a user that does not belong to the account' do
      it 'raises ArgumentError' do
        stranger = create(:user)

        expect do
          described_class.promote_to_owner!(account: account, user: stranger)
        end.to raise_error(ArgumentError, /does not belong/)
      end
    end

    context 'with missing arguments' do
      it 'raises ArgumentError when account is nil' do
        expect do
          described_class.promote_to_owner!(account: nil, user: user)
        end.to raise_error(ArgumentError, /account is required/)
      end

      it 'raises ArgumentError when user is nil' do
        expect do
          described_class.promote_to_owner!(account: account, user: nil)
        end.to raise_error(ArgumentError, /user is required/)
      end
    end

    context 'when the user is a SaaS SuperAdmin' do
      it 'raises ArgumentError — super admins already have full bypass' do
        super_admin_user = create(:super_admin)
        create(:account_user, account: account, user: super_admin_user)

        expect do
          described_class.promote_to_owner!(account: account, user: super_admin_user)
        end.to raise_error(ArgumentError, /SuperAdmin/)
      end

      it 'does not create an owner team' do
        super_admin_user = create(:super_admin)
        create(:account_user, account: account, user: super_admin_user)

        begin
          described_class.promote_to_owner!(account: account, user: super_admin_user)
        rescue ArgumentError
          # expected
        end

        expect(account.teams.where(name: 'owner')).to be_empty
      end
    end

    context 'when an owner team already exists with wrong role' do
      it 'updates the beclinic_role to dono' do
        team = create(:team, account: account, name: 'owner')
        team.beclinic_profile.update!(beclinic_role: 'gerente')

        described_class.promote_to_owner!(account: account, user: user)

        expect(team.reload.beclinic_role).to eq('dono')
      end
    end
  end
end
