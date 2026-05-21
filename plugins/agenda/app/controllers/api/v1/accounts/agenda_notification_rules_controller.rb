class Api::V1::Accounts::AgendaNotificationRulesController < Api::V1::Accounts::BaseController
  before_action :agenda_notification_rule, only: [:show, :update, :destroy, :toggle]
  before_action :check_authorization

  def index
    @rules = Current.account.agenda_notification_rules.ordered
  end

  def show; end

  def create
    @rule = Current.account.agenda_notification_rules.create!(notification_rule_params)
    render :show, status: :created
  end

  def update
    @rule.update!(notification_rule_params)
    render :show
  end

  def destroy
    @rule.destroy!
    head :ok
  end

  # PATCH /accounts/:account_id/agenda_notification_rules/:id/toggle
  # Alterna o estado enabled/disabled da regra
  def toggle
    @rule.update!(enabled: !@rule.enabled)
    render :show
  end

  private

  def agenda_notification_rule
    @rule ||= Current.account.agenda_notification_rules.find(params[:id])
  end

  def notification_rule_params
    permitted = params.require(:agenda_notification_rule).permit(
      :title, :rule_type, :icon, :icon_color, :iconColor,
      :trigger_offset_hours, :message_template, :message,
      :enabled, :position,
      inboxes: [:label, :inbox_id, :color]
    )

    # Normaliza campos enviados pelo frontend (camelCase → snake_case)
    if permitted.key?(:message)
      val = permitted.delete(:message)
      permitted[:message_template] ||= val
    end

    if permitted.key?(:iconColor)
      val = permitted.delete(:iconColor)
      permitted[:icon_color] ||= val
    end

    permitted
  end
end
