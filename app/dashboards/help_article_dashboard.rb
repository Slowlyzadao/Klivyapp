require 'administrate/base_dashboard'

class HelpArticleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    title: Field::String,
    body: RichTextField,
    category: Field::Select.with_options(collection: -> { HelpCategory.ordered.pluck(:slug) }),
    status: Field::Select.with_options(collection: HelpArticle::STATUSES),
    video_url: Field::String,
    next_steps: Field::Text,
    position: Field::Number,
    deleted_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    title
    category
    status
    position
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    category
    status
    video_url
    next_steps
    body
    position
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    title
    category
    status
    video_url
    position
    next_steps
    body
  ].freeze

  COLLECTION_FILTERS = {
    published: ->(resources) { resources.where(status: 'published') },
    draft: ->(resources) { resources.where(status: 'draft') }
  }.freeze

  def display_resource(article)
    article.title
  end

  def self.resource_name(opts = {})
    opts[:count] == 1 ? 'Artigo' : 'Ajuda - Artigos'
  end
end
