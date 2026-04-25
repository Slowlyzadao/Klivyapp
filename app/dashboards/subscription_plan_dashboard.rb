require 'administrate/base_dashboard'

class SubscriptionPlanDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id:            Field::Number,
    name:          Field::String,
    price_monthly: Field::Number,
    active:        Field::Boolean,
    created_at:    Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name price_monthly active created_at].freeze
  SHOW_PAGE_ATTRIBUTES  = %i[id name price_monthly active created_at].freeze
  FORM_ATTRIBUTES       = %i[name price_monthly active].freeze

  def display_resource(plan)
    plan.name
  end
end
