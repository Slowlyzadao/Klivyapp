class Api::V1::Accounts::FormTemplatesController < Api::V1::Accounts::BaseController
  before_action :fetch_template, only: [:show, :update, :destroy]
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/form_templates
  def index
    @form_templates = FormTemplate
                      .for_account_or_global(current_account.id)
                      .active
                      .order(:name)

    @form_templates = @form_templates.by_type(params[:template_type]) if params[:template_type].present?
    @form_templates = @form_templates.by_specialty(params[:specialty]) if params[:specialty].present?

    render 'api/v1/accounts/form_templates/index', format: :json
  end

  # GET /api/v1/accounts/:account_id/form_templates/:id
  def show
    render 'api/v1/accounts/form_templates/show', format: :json
  end

  # POST /api/v1/accounts/:account_id/form_templates
  def create
    @form_template = FormTemplate.new(
      template_params.merge(account: current_account, created_by: current_user)
    )
    authorize @form_template

    if @form_template.save
      render 'api/v1/accounts/form_templates/show', format: :json, status: :created
    else
      render json: { errors: @form_template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/accounts/:account_id/form_templates/:id
  def update
    authorize @form_template

    if @form_template.update(template_params)
      render 'api/v1/accounts/form_templates/show', format: :json
    else
      render json: { errors: @form_template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/accounts/:account_id/form_templates/:id
  def destroy
    authorize @form_template

    @form_template.soft_delete!
    head :ok
  end

  private

  def fetch_template
    @form_template = FormTemplate.for_account_or_global(current_account.id).active.find(params[:id])
    authorize @form_template
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Template não encontrado' }, status: :not_found
  end

  def template_params
    params.require(:form_template).permit(:name, :template_type, :specialty, :is_global, :active, fields: [])
  end
end
