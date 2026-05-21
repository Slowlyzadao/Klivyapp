class ReportPolicy < ApplicationPolicy
  REPORT_VIEW_PERMS = %i[
    view_overview view_conversation view_agent view_label view_inbox
    view_team view_csat view_sla view_bot view_agenda
  ].freeze

  def view?
    return true if @account_user.administrator?

    REPORT_VIEW_PERMS.any? { |perm| beclinic_can?(:reports, perm) }
  end
end

ReportPolicy.prepend_mod_with('ReportPolicy')
