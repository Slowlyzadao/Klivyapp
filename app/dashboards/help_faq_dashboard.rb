require 'administrate/base_dashboard'

class HelpFaqDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id:       Field::Number,
    question: Field::String.with_options(searchable: true),
    answer:   Field::Text,
    category: Field::Select.with_options(
                collection: -> { HelpCategory.ordered.pluck(:slug) rescue HelpArticle::CATEGORIES },
                include_blank: false
              ),
    position: Field::Number,
    active:   Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id question category position active created_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id question answer category position active created_at updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[question answer category position active].freeze

  def display_resource(help_faq)
    "##{help_faq.id} #{help_faq.question.truncate(60)}"
  end
end
