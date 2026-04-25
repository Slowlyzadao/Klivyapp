class KlivyMailer < Devise::Mailer
  default from: ENV.fetch('KLIVY_MAILER_SENDER', 'Klivy <no-reply@klivy.app>')
  layout 'klivy_mailer'

  def confirmation_instructions(record, token, opts = {})
    @account = params && params[:account]
    @account_user = record.account_users.find_by(account: @account) if @account
    @inviter = @account_user&.inviter
    super
  end

  def reset_password_instructions(record, token, opts = {})
    @account = params && params[:account]
    super
  end

  def password_change(record, opts = {})
    @account = params && params[:account]
    super
  end
end
