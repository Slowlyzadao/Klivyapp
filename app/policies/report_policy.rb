class ReportPolicy < ApplicationPolicy
  # Endpoints de Reports são compartilhados entre todas as abas
  # (Visão geral, Conversas, Por agente, Por etiqueta, Por caixa, Por time,
  # CSAT, SLA, Bot, Agenda). O acesso à API basta o usuário ter qualquer
  # uma das view-perms — a aba específica é gateada pelo router/sidebar.
  REPORT_VIEW_PERMS = %i[
    view_overview
    view_conversation
    view_agent
    view_label
    view_inbox
    view_team
    view_csat
    view_sla
    view_bot
    view_agenda
  ].freeze

  def view?
    return true if @account_user.administrator?

    REPORT_VIEW_PERMS.any? { |perm| beclinic_can?(:reports, perm) }
  end
end

ReportPolicy.prepend_mod_with('ReportPolicy')
