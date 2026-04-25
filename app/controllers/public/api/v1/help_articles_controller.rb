class Public::Api::V1::HelpArticlesController < PublicController
  def index
    articles = HelpArticle.published.ordered
    articles = articles.by_category(params[:category]) if params[:category].present?
    articles = HelpArticle.search(params[:q]).published if params[:q].present?

    render json: articles.map { |a| serialize(a) }
  end

  def show
    article = HelpArticle.published.find(params[:id])
    render json: serialize(article)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Artigo não encontrado.' }, status: :not_found
  end

  def categories
    cats = HelpCategory.ordered
    render json: cats.map { |c| serialize_category(c) }
  rescue StandardError
    render json: []
  end

  def faqs
    items = HelpFaq.active.ordered
    render json: items.map { |f| serialize_faq(f) }
  rescue StandardError
    render json: []
  end

  private

  def serialize(article)
    {
      id:           article.id,
      title:        article.title,
      body:         article.body.to_s,
      category:     article.category,
      status:       article.status,
      video_url:    article.video_url,
      next_steps:   article.next_steps.to_s,
      position:     article.position,
      reading_time: article.reading_time,
      created_at:   article.created_at,
      updated_at:   article.updated_at,
    }
  end

  def serialize_faq(faq)
    {
      id:       faq.id,
      question: faq.question,
      answer:   faq.answer,
      cat:      faq.category,
      position: faq.position,
    }
  end

  def serialize_category(cat)
    {
      id:          cat.slug,
      name:        cat.name,
      description: cat.description,
      icon_svg:    cat.icon_svg,
      icon_class:  cat.icon_class,
      hidden:      cat.hidden,
      position:    cat.position,
    }
  end
end
