class SuperAdmin::HelpFaqsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.ordered
  end

  def resource_params
    params.require(resource_class.model_name.param_key)
          .permit(dashboard.permitted_attributes(action_name))
  end
end
