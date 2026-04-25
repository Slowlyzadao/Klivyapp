require 'administrate/base_dashboard'

class HelpCategoryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id:          Field::Number,
    name:        Field::String,
    description: Field::String,
    slug:        Field::String,
    icon_class:  Field::String,
    icon_svg:    Field::Text,
    position:    Field::Number,
    hidden:      Field::Boolean,
    created_at:  Field::DateTime,
    updated_at:  Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name slug position hidden created_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id name description slug icon_class icon_svg position hidden created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[name description slug icon_class icon_svg position hidden].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(category)
    category.name
  end
end
