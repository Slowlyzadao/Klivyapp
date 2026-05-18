class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact
    permitted_params[:selected_feature_flags] = params[:enabled_features].keys.map(&:to_sym) if params[:enabled_features].present?
    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def destroy
    account = Account.find(params[:id])

    DeleteObjectJob.perform_later(account) if account.present?
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account deletion is in progress.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  # Per-account "Bea" configuration screen.
  def bea
    @account = Account.find(params[:id])
    @setting = @account.ai_agent_setting || @account.build_ai_agent_setting
    @global = AiAgent::GlobalSetting.current
    @personas = AiAgent::PersonaTemplate.order(:name)
    @available_tools = AiAgent::ToolDefinition.enabled.order(:name)
    @month_tokens = AiAgent::UsageCounter.monthly_total(account_id: @account.id)
    @month_cost_cents = AiAgent::UsageCounter.monthly_cost_cents(account_id: @account.id)
  end

  def update_bea
    @account = Account.find(params[:id])
    @global = AiAgent::GlobalSetting.current
    setting = @account.ai_agent_setting || @account.build_ai_agent_setting

    setting.assign_attributes(bea_setting_params(setting))
    clamp_against_global!(setting)

    if setting.save
      AiAgent::AuditLog.record(
        scope: 'account',
        action: 'update_settings',
        actor: current_super_admin,
        account_id: @account.id,
        ip: request.remote_ip,
        changes: setting.previous_changes.except('updated_at')
      )
      redirect_to bea_super_admin_account_path(@account), notice: 'Configurações da Bea atualizadas para esta conta.'
    else
      redirect_to bea_super_admin_account_path(@account), alert: setting.errors.full_messages.join(', ')
    end
  end

  private

  def bea_setting_params(setting)
    permitted = params.require(:bea).permit(
      :enabled, :chat_model, :monthly_token_budget,
      :max_tokens_per_conversation, :persona_id,
      :system_prompt_prefix,
      # Sprint E (LGPD/CFM 2.454/2026): responsável técnico identificável.
      :responsible_physician_id,
      :responsible_physician_council,
      :responsible_physician_crm,
      enabled_tools: []
    )

    # Checkboxes for enabled_tools come as 'tool_key' => '1' or array; normalize.
    permitted[:enabled_tools] = Array(permitted[:enabled_tools]).reject(&:blank?) if permitted.key?(:enabled_tools)
    # Conselho sempre uppercase pra bater com a validação no model.
    permitted[:responsible_physician_council] = permitted[:responsible_physician_council].to_s.strip.upcase if permitted.key?(:responsible_physician_council)
    permitted
  end

  # Account values cannot exceed the global ceiling (clamp at write time).
  def clamp_against_global!(setting)
    if setting.max_tokens_per_conversation.present?
      setting.max_tokens_per_conversation = [setting.max_tokens_per_conversation, @global.max_tokens_per_conversation].min
    end
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
