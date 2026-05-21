class Api::V1::Accounts::ClinicProfileController < Api::V1::Accounts::BaseController
  before_action :fetch_account
  after_action :verify_authorized

  def show
    authorize @account, policy_class: ClinicProfilePolicy
    render json: serialize(@account)
  end

  def update
    authorize @account, policy_class: ClinicProfilePolicy

    profile = @account.beclinic_profile
    if profile.update(profile_params)
      render json: serialize(@account)
    else
      render json: { error: profile.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def serialize(account)
    {
      default_specialty: account.default_specialty,
      enabled_specialties: account.enabled_specialties || []
    }
  end

  def profile_params
    permitted = params.permit(:default_specialty, enabled_specialties: [])
    # `enabled_specialties: []` aceita só valores escalares — limpa duplicatas
    # e strings vazias antes de gravar.
    if permitted[:enabled_specialties].is_a?(Array)
      permitted[:enabled_specialties] = permitted[:enabled_specialties]
                                        .map { |v| v.to_s.strip }
                                        .reject(&:blank?)
                                        .uniq
    end
    permitted
  end

  def fetch_account
    @account = Current.account
  end
end
