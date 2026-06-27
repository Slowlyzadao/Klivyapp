module Financial
  # Mailer pra notificar AUDITOR/ADMIN que o export assíncrono de AuditLogs
  # ficou pronto. Disparado pelo AuditLogsExportJob após upload ao R2.
  #
  # Link expira em 24h (signed URL do Active Storage).
  class AuditExportMailer < ::ApplicationMailer
    def export_ready(user:, account:, download_url:, row_count:, from:, to:, expires_at:)
      @user = user
      @account = account
      @download_url = download_url
      @row_count = row_count
      @from = from
      @to = to
      @expires_at = expires_at

      ensure_current_account(account)

      mail(
        to: user.email,
        subject: "[Klivy] Export de auditoria pronto (#{from} → #{to})"
      ) do |format|
        format.html
        format.text
      end
    end
  end
end
