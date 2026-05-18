# config/initializers/active_storage_account_scoping.rb
#
# Prefixa o `key` de cada ActiveStorage::Blob criado com `accounts/<account_id>/`
# quando `Current.account` está setado.
#
# Por que: blobs ficam fisicamente segregados por tenant no bucket R2.
# Ganhos:
#   - Auditoria forense direta (`r2 ls accounts/42/`)
#   - Lifecycle policies por tenant
#   - Backup/migração por conta
#   - "Delete account" (LGPD) → `r2 rm --recursive accounts/42/` resolve em uma operação
#
# Comportamento:
#   - Se Current.account está setado (request HTTP, Sidekiq job que setou)
#     → key = "accounts/<id>/<random>"
#   - Se Current.account é nil (job de sistema, console manual, seed)
#     → key permanece random na raiz (fallback Rails default)
#   - Idempotente: se key já tem prefixo `accounts/`, não duplica
#
# Limitações conhecidas (documentadas):
#   - Direct uploads (browser → R2 direto) bypass este hook. Hoje ok pois
#     DIRECT_UPLOADS_ENABLED não está ativo. Se ativar no futuro, o presigned
#     URL precisa ser gerado server-side com a key prefixada manualmente.
#   - Jobs que criam blobs (ex.: AvatarFromGravatarJob) sem setar Current.account
#     vão escrever na raiz. Não é vazamento — só fica menos auditável.

Rails.application.config.to_prepare do
  ActiveStorage::Blob.class_eval do
    before_create :beclinic_scope_key_to_account

    def beclinic_scope_key_to_account
      account_id = Current.account&.id
      return unless account_id
      return if key.to_s.start_with?('accounts/')

      self.key = "accounts/#{account_id}/#{key}"
    end
  end
end
