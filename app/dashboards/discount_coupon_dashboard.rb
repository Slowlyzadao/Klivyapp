require 'administrate/base_dashboard'

class DiscountCouponDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id:          Field::Number,
    code:        Field::String,
    description: Field::String,
    kind:        Field::String,
    active:      Field::Boolean,
    created_at:  Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id code description kind active created_at].freeze
  SHOW_PAGE_ATTRIBUTES  = %i[id code description kind active created_at].freeze
  FORM_ATTRIBUTES       = %i[code description kind active].freeze

  def display_resource(coupon)
    coupon.code
  end
end
