class Public::Api::V1::SubscriptionPlansController < ActionController::API
  def show
    plan = ::SubscriptionPlan.active.find_by!(slug: params[:slug])
    render json: serialize(plan)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Plano não encontrado' }, status: :not_found
  end

  private

  def serialize(plan)
    {
      id:             plan.id,
      slug:           plan.slug,
      name:           plan.name,
      description:    plan.description,
      price_monthly:  plan.price_monthly.to_f,
      price_yearly:   plan.price_yearly&.to_f,
      color:          plan.color,
      features:       plan.features || [],
      limits:         plan.limits || {},
    }
  end
end
