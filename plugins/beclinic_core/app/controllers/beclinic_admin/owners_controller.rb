module BeclinicAdmin
  # Standalone admin page for manually promoting a user to Owner of an account.
  # Inherits from SuperAdmin::ApplicationController to reuse its Devise-based
  # super_admin authentication (authenticate_super_admin! before_action), but
  # overrides the layout with a minimal standalone one — the Chatwoot super_admin
  # layout uses Administrate's Namespace.resources scanner (see administrate-0.20.1
  # /lib/administrate/namespace.rb:14) which would choke on unknown controllers.
  # This controller's path is 'beclinic_admin/owners' — deliberately NOT under
  # the 'super_admin/' path so Administrate's scanner skips it entirely.
  class OwnersController < ::SuperAdmin::ApplicationController
    layout 'beclinic_admin'

    before_action :load_account, only: [:show, :promote]

    def index
      @accounts = ::Account.order(:id).includes(:account_users).page(params[:page]).per(25)
      @owners_by_account = load_owners_for(@accounts)
    end

    def show
      # Exclude SaaS SuperAdmins — they already have full-system bypass
      # (beclinic_permissible.rb#beclinic_super_admin?) and promoting them
      # to the account-level Owner team is redundant and confusing.
      @account_users = @account.account_users
                               .joins(:user)
                               .where(users: { type: nil })
                               .includes(:user)
                               .order(:created_at)
      @current_owner_ids = owner_user_ids(@account)
    end

    def promote
      user = ::User.find(params[:user_id])
      result = BeclinicCore::AccountSetup.promote_to_owner!(account: @account, user: user)

      flash[:notice] = if result.promoted
                         "#{user.email} foi promovido a Proprietário da conta #{@account.name}."
                       else
                         "#{user.email} já era Proprietário da conta #{@account.name}."
                       end
      redirect_to beclinic_admin_owner_path(@account)
    rescue ActiveRecord::RecordNotFound
      flash[:error] = 'Usuário não encontrado.'
      redirect_to beclinic_admin_owner_path(@account)
    rescue ArgumentError => e
      flash[:error] = "Não foi possível promover: #{e.message}"
      redirect_to beclinic_admin_owner_path(@account)
    end

    private

    def load_account
      @account = ::Account.find(params[:id])
    end

    def load_owners_for(accounts)
      account_ids = accounts.map(&:id)
      teams = ::Team.joins(:beclinic_profile)
                    .where(beclinic_team_profiles: { beclinic_role: 'dono' })
                    .where(account_id: account_ids)
                    .includes(:members)

      teams.each_with_object({}) do |team, hash|
        regular_members = team.members.reject { |u| u.is_a?(::SuperAdmin) }
        next if regular_members.empty?

        hash[team.account_id] ||= []
        hash[team.account_id].concat(regular_members)
      end
    end

    def owner_user_ids(account)
      team = account.teams.joins(:beclinic_profile)
                    .where(beclinic_team_profiles: { beclinic_role: 'dono' })
                    .first
      return [] unless team

      team.members.reject { |u| u.is_a?(::SuperAdmin) }.map(&:id)
    end
  end
end
