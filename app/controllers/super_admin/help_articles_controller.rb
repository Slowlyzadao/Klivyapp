class SuperAdmin::HelpArticlesController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.where(deleted_at: nil).order(:category, :position, :created_at)
  end

  def destroy
    requested_resource.soft_delete!
    redirect_to super_admin_help_articles_path,
                notice: 'Artigo excluído com sucesso.'
  end

  private

  def resource_params
    params.require(:help_article).permit(
      :title, :body, :next_steps, :category, :status, :video_url, :position
    )
  end
end
