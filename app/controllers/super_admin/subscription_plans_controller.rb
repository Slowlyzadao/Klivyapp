class SuperAdmin::SubscriptionPlansController < SuperAdmin::ApplicationController
  before_action :find_plan, only: [:update, :destroy]

  def index
    respond_to do |format|
      format.html { render :index }
      format.json { render json: ::SubscriptionPlan.ordered }
    end
  end

  def create
    plan = ::SubscriptionPlan.new(plan_params)
    if plan.save
      render json: plan, status: :created
    else
      render json: { errors: plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @plan.update(plan_params)
      render json: @plan
    else
      render json: { errors: @plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @plan.destroy
    head :no_content
  end

  private

  def find_plan
    @plan = ::SubscriptionPlan.find(params[:id])
  end

  def plan_params
    permitted = params.require(:subscription_plan).permit(
      :name, :description, :price_monthly, :price_yearly,
      :color, :active, :display_order, features: []
    )
    raw_limits = params.dig(:subscription_plan, :limits)
    if raw_limits
      permitted[:limits] = raw_limits
        .to_unsafe_h
        .slice('agents', 'inboxes', 'captain_responses', 'captain_documents', 'emails')
        .transform_values { |v| v.present? ? v.to_i : nil }
        .compact
    end
    permitted
  end
end
