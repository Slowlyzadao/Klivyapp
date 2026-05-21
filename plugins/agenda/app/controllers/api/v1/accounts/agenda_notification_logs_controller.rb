class Api::V1::Accounts::AgendaNotificationLogsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/agenda_notification_logs
  # Suporta filtros via query params:
  #   ?status=sent|failed|skipped
  #   ?rule_id=X
  #   ?per_page=25&page=1
  def index
    @logs = Current.account.agenda_notification_logs
                   .includes(:agenda_event, :agenda_notification_rule)
                   .order(sent_at: :desc)

    @logs = @logs.where(status: params[:status])           if params[:status].present?
    @logs = @logs.where(agenda_notification_rule_id: params[:rule_id]) if params[:rule_id].present?

    per_page   = (params[:per_page] || 25).to_i.clamp(1, 100)
    @logs      = @logs.page(params[:page]).per(per_page)
    @meta      = { total: @logs.total_count, page: @logs.current_page, per_page: per_page }
  end
end
