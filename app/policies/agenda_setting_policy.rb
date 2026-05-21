class AgendaSettingPolicy < ApplicationPolicy
  # Auditoria A-5: `show?` ganha fallback Klivy explícito `agenda.view_settings`
  # (era aberto pra qualquer agente da conta, agora prefere a perm). `update?`
  # exige `agenda.manage_schedules` (a perm mais "core" de edição de settings
  # da agenda — manage_online_booking/_services/_notifications são sub-domínios
  # com controllers próprios). Admin nativo continua passando.
  def show?
    administrator? || beclinic_can?(:agenda, :view_settings) || account_user?
  end

  def update?
    administrator? || beclinic_can?(:agenda, :manage_schedules)
  end

  private

  def account_user?
    @account_user.present?
  end

  def administrator?
    @account_user&.administrator?
  end
end
