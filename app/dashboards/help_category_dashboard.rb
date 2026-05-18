require 'administrate/base_dashboard'

class HelpCategoryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    slug: Field::String,
    description: Field::String,
    icon_class: Field::String,
    icon_svg: Field::Text,
    position: Field::Number,
    hidden: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    slug
    position
    hidden
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    slug
    description
    icon_class
    icon_svg
    position
    hidden
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    slug
    description
    icon_class
    icon_svg
    position
    hidden
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(category)
    category.name
  end

  # Hardcoded para não depender do reload do YAML — garante que o nome
  # do recurso exiba "Categoria" / "Ajuda - Categorias" mesmo se as keys
  # I18n do administrate.pt_BR.yml ainda não tiverem sido recarregadas
  # após boot do server.
  def self.resource_name(opts = {})
    opts[:count] == 1 ? 'Categoria' : 'Ajuda - Categorias'
  end
end
