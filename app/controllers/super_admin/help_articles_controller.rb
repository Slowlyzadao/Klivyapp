class SuperAdmin::HelpArticlesController < SuperAdmin::ApplicationController
  def destroy
    requested_resource.soft_delete!
    redirect_to super_admin_help_articles_path, notice: 'Artigo excluído.'
  end

  def scoped_resource
    resource_class.visible.ordered
  end

  def resource_params
    params.require(resource_class.model_name.param_key)
          .permit(dashboard.permitted_attributes(action_name))
  end

  # Após salvar, ficar na própria tela de edição (em vez de cair na show
  # que renderiza o body inteiro como texto e fica visualmente confuso).
  def after_resource_updated_path(resource)
    edit_super_admin_help_article_path(resource)
  end

  def after_resource_created_path(resource)
    edit_super_admin_help_article_path(resource)
  end
end
