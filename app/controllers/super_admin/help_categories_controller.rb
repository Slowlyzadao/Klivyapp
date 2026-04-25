class SuperAdmin::HelpCategoriesController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.ordered
  end

  private

  def resource_params
    params.require(:help_category).permit(:name, :description, :slug, :icon_class, :icon_svg, :position, :hidden)
  end
end
