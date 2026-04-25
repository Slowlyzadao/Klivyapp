class SuperAdmin::HelpFaqsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.ordered
  end

  def resource_params
    params.require(:help_faq).permit(:question, :answer, :category, :position, :active)
  end
end
