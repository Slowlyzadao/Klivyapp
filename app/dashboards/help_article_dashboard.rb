require 'administrate/base_dashboard'

class HelpArticleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id:         Field::Number,
    title:      Field::String.with_options(searchable: true),
    body:       RichTextField,
    category:   Field::Select.with_options(
                  collection: -> { HelpCategory.ordered.pluck(:slug) rescue HelpArticle::CATEGORIES },
                  include_blank: false
                ),
    status:     Field::Select.with_options(
                  collection: HelpArticle::STATUSES,
                  include_blank: false
                ),
    video_url:  Field::String,
    next_steps: Field::Text,
    position:   Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    title
    category
    status
    position
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    body
    category
    status
    video_url
    next_steps
    position
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    title
    body
    next_steps
    category
    status
    video_url
    position
  ].freeze

  COLLECTION_FILTERS = {
    published: ->(resources) { resources.where(status: 'published') },
    draft:     ->(resources) { resources.where(status: 'draft') },
  }.freeze

  def display_resource(help_article)
    "##{help_article.id} #{help_article.title}"
  end
end
