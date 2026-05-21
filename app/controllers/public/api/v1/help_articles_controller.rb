class Public::Api::V1::HelpArticlesController < PublicController
  def index
    scope = HelpArticle.published
    scope = scope.by_category(params[:category]) if params[:category].present?
    scope = scope.search(params[:q])             if params[:q].present?

    render json: scope.ordered.map { |article| serialize(article) }
  end

  def show
    article = HelpArticle.published.find(params[:id])
    render json: serialize(article)
  end

  def faqs
    category_lookup = HelpCategory.ordered.pluck(:slug, :name).to_h
    rows = HelpFaq.visible.ordered.map do |faq|
      {
        id: faq.id,
        cat: faq.category,
        catName: category_lookup[faq.category] || faq.category,
        question: faq.question,
        answer: faq.answer,
        tags: faq.tags_array
      }
    end
    render json: rows
  rescue ActiveRecord::StatementInvalid
    # help_faqs table not yet migrated — frontend falls back to static FAQS.
    render json: []
  end

  def categories
    rows = HelpCategory.ordered.map do |c|
      {
        id: c.slug,
        name: c.name,
        description: c.description,
        icon_class: c.icon_class,
        icon_svg: c.icon_svg,
        hidden: c.hidden,
        position: c.position
      }
    end
    render json: rows
  end

  private

  def serialize(article)
    {
      id: article.id,
      title: article.title,
      body: article.body,
      category: article.category,
      status: article.status,
      video_url: article.video_url,
      next_steps: article.next_steps.to_s,
      position: article.position,
      reading_time: article.reading_time,
      created_at: article.created_at,
      updated_at: article.updated_at
    }
  end
end
