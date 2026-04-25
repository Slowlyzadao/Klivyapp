class SuperAdmin::DiscountCouponsController < SuperAdmin::ApplicationController
  before_action :find_coupon, only: [:update, :destroy]

  def index
    respond_to do |format|
      format.html { render :index }
      format.json { render json: ::DiscountCoupon.ordered }
    end
  end

  def create
    coupon = ::DiscountCoupon.new(coupon_params)
    if coupon.save
      render json: coupon, status: :created
    else
      render json: { errors: coupon.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @coupon.update(coupon_params)
      render json: @coupon
    else
      render json: { errors: @coupon.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @coupon.destroy
    head :no_content
  end

  private

  def find_coupon
    @coupon = ::DiscountCoupon.find(params[:id])
  end

  def coupon_params
    params.require(:discount_coupon).permit(
      :code, :description, :kind, :discount_percent, :discount_amount,
      :trial_days, :months_duration, :active,
      :max_uses, :expires_at
    )
  end
end
