module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  thread_mattr_accessor :captain_resolve_reason
  # PR #8 follow-up (2026-05-14): captura IP da requisição para AuditLogs.
  # Setado em before_action de controllers que precisam (ex.: agenda_services).
  # `Current.try(:request_ip)` em models retorna nil se não foi setado — não quebra.
  thread_mattr_accessor :request_ip

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.captain_resolve_reason = nil
    Current.request_ip = nil
  end
end
