module BeclinicCore
  # Service to promote an AccountUser to Owner of an account (UI label: "Proprietário").
  #
  # Promotion means: the user belongs to a Team whose beclinic_profile has
  # beclinic_role = 'dono'. BeclinicPermissible#beclinic_team_for returns the
  # first team the user belongs to in the account, so we remove the user from
  # any other teams in this account to guarantee the Owner team is the one
  # resolved on permission checks.
  #
  # Idempotent: calling it again for a user that is already the Owner is a
  # no-op and returns the existing team.
  #
  # Never touches User#type (SuperAdmin) — that is reserved for SaaS owners.
  class AccountSetup
    OWNER_TEAM_NAME = 'owner'.freeze

    Result = Struct.new(:team, :promoted, keyword_init: true)

    def self.promote_to_owner!(account:, user:)
      new(account: account, user: user).promote_to_owner!
    end

    def initialize(account:, user:)
      @account = account
      @user = user
    end

    def promote_to_owner!
      raise ArgumentError, 'account is required' if @account.nil?
      raise ArgumentError, 'user is required' if @user.nil?
      raise ArgumentError, 'user does not belong to account' unless account_user_exists?
      raise ArgumentError, 'cannot promote a SaaS SuperAdmin — they already have full bypass' if @user.is_a?(::SuperAdmin)

      ActiveRecord::Base.transaction do
        team = find_or_create_owner_team
        already_owner = only_member_of?(team)

        unless already_owner
          remove_user_from_other_account_teams(except: team)
          team.team_members.find_or_create_by!(user: @user)
        end

        Result.new(team: team, promoted: !already_owner)
      end
    end

    private

    def account_user_exists?
      AccountUser.exists?(account_id: @account.id, user_id: @user.id)
    end

    def find_or_create_owner_team
      team = @account.teams.find_by(name: OWNER_TEAM_NAME)
      return team if team && team.beclinic_role == 'dono'

      if team
        team.beclinic_profile.update!(beclinic_role: 'dono')
        team.update!(is_preset: true) if team.respond_to?(:is_preset=) && !team.is_preset
        return team
      end

      @account.teams.create!(
        name: OWNER_TEAM_NAME,
        beclinic_role: 'dono',
        is_preset: true,
        permissions: {}
      )
    end

    def only_member_of?(team)
      user_account_teams = @user.teams.where(account_id: @account.id)
      user_account_teams.count == 1 && user_account_teams.first.id == team.id
    end

    def remove_user_from_other_account_teams(except:)
      other_team_ids = @user.teams.where(account_id: @account.id).where.not(id: except.id).pluck(:id)
      return if other_team_ids.empty?

      TeamMember.where(user_id: @user.id, team_id: other_team_ids).destroy_all
    end
  end
end
