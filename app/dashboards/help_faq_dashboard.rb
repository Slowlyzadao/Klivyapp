require 'administrate/base_dashboard'

class HelpFaqDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    question: Field::String,
    answer: Field::Text,
    category: Field::Select.with_options(collection: -> { HelpCategory.ordered.pluck(:slug) }),
    tags: Field::String.with_options(searchable: true),
    position: Field::Number,
    hidden: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    question
    category
    position
    hidden
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    question
    answer
    category
    tags
    position
    hidden
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    question
    answer
    category
    tags
    position
    hidden
  ].freeze

  COLLECTION_FILTERS = {
    visible: ->(resources) { resources.where(hidden: false) },
    hidden: ->(resources) { resources.where(hidden: true) }
  }.freeze

  def display_resource(faq)
    faq.question
  end

  def self.resource_name(opts = {})
    opts[:count] == 1 ? 'Pergunta Frequente' : 'Ajuda - Perguntas Frequentes'
  end
end
