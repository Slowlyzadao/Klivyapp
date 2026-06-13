class Api::V1::Accounts::ClinicProfileController < Api::V1::Accounts::BaseController
  before_action :fetch_account
  after_action :verify_authorized

  # Chaves clínicas gravadas em account.custom_attributes — casam 1:1 com o
  # DocumentTemplates::Readers::ClinicReader (fonte das variáveis clinic.*).
  CLINIC_KEYS = %i[
    fantasy_name cnpj
    address_street address_number address_complement address_neighborhood
    address_city address_state address_zip
    phone website
  ].freeze

  def show
    authorize @account, policy_class: ClinicProfilePolicy
    render json: serialize(@account)
  end

  def update
    authorize @account, policy_class: ClinicProfilePolicy

    ActiveRecord::Base.transaction do
      # Aba de especialidades (uso legado deste mesmo controller) — só quando
      # os params de especialidade vierem.
      @account.beclinic_profile.update!(profile_params) if specialty_params?
      apply_clinic_data
      attach_logo if params[:blob_id].present?
    end
    render json: serialize(@account)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def serialize(account)
    ca = (account.custom_attributes || {})
    {
      default_specialty: account.default_specialty,
      enabled_specialties: account.enabled_specialties || [],
      name: account.name, # razão/nome da conta (pré-preenchimento)
      fantasy_name: ca['fantasy_name'],
      cnpj: ca['cnpj'].presence || billing_cnpj,
      address_street: ca['address_street'],
      address_number: ca['address_number'],
      address_complement: ca['address_complement'],
      address_neighborhood: ca['address_neighborhood'],
      address_city: ca['address_city'],
      address_state: ca['address_state'],
      address_zip: ca['address_zip'],
      phone: ca['phone'].presence || billing_phone,
      website: ca['website'],
      logo_url: account.logo.attached? ? url_for(account.logo) : nil
    }
  end

  # Pré-preenchimento de CNPJ/telefone a partir do cadastro de billing (Asaas)
  # quando ainda não há valor manual — espelha o fallback do ClinicReader.
  def billing_customer
    return @billing_customer if defined?(@billing_customer)

    @billing_customer =
      if defined?(::Billing::Subscription) && defined?(::Billing::Customer)
        sub = ::Billing::Subscription.where(account_id: @account.id).order(created_at: :desc).first
        sub && ::Billing::Customer.find_by(asaas_customer_id: sub.asaas_customer_id)
      end
  rescue StandardError
    @billing_customer = nil
  end

  def billing_cnpj
    billing_customer&.cpf_cnpj
  end

  def billing_phone
    billing_customer&.phone
  end

  def apply_clinic_data
    data = clinic_data_params
    return if data.empty?

    @account.custom_attributes = (@account.custom_attributes || {}).merge(data)
    @account.save!
  end

  # Anexa o logo a partir do signed_id (blob_id) gerado pelo endpoint genérico
  # POST /upload. O scoping accounts/<id>/ do blob é garantido pelo
  # active_storage_account_scoping (Current.account já setado no BaseController).
  def attach_logo
    blob = ActiveStorage::Blob.find_signed(params[:blob_id])
    return unless blob&.content_type.to_s.start_with?('image/')

    @account.logo.attach(blob)
  end

  def clinic_data_params
    params.permit(*CLINIC_KEYS).to_h.symbolize_keys.transform_values { |v| v.to_s.strip }
  end

  def specialty_params?
    params.key?(:default_specialty) || params.key?(:enabled_specialties)
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
