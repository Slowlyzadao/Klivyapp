module Financial
  # Gera export CSV de Financial::AuditLog assíncrono, sobe pro R2 via
  # ActiveStorage e envia email com link assinado (24h).
  #
  # Disparado quando o export síncrono passa de MAX_SYNC_ROWS (50k) no
  # AuditLogsController. Canon Fase 5 (housekeeping pós-reescrita).
  #
  # Segurança:
  #   - Job é scoped por account_id (multi-tenant — memory project_active_storage_account_scoping)
  #   - PII sanitization espelha o sync (slice changed_keys + redact PII_KEYS_DROP)
  #   - Link expira em 24h via ActiveStorage::Blob#service_url(expires_in:)
  #
  # Idempotência: o job é seguro de re-executar — gera novo blob a cada call;
  # múltiplos clicks no botão criam múltiplos exports (separados por timestamp
  # no filename). Aceitável pra esta operação rara.
  class AuditLogsExportJob < ApplicationJob
    queue_as :default

    PII_KEYS_DROP = %w[email phone telefone cpf cnpj rg full_name name].freeze
    EXPORT_TTL = 24.hours

    def perform(account_id:, user_id:, from:, to:, filters: {})
      account = ::Account.find(account_id)
      user = ::User.find(user_id)

      scope = build_scope(account: account, from: from, to: to, filters: filters)
      total = scope.count

      csv_content = build_csv(scope)
      filename = build_filename(account: account, from: from, to: to)

      blob = upload_to_storage(content: csv_content, filename: filename, account: account)
      download_url = signed_url_for(blob)

      Financial::AuditExportMailer
        .export_ready(
          user: user,
          account: account,
          download_url: download_url,
          row_count: total,
          from: from,
          to: to,
          expires_at: EXPORT_TTL.from_now
        )
        .deliver_later
    end

    private

    def build_scope(account:, from:, to:, filters:)
      scope = ::Financial::AuditLog
                .for_account(account.id)
                .recent_first
                .where(created_at: Date.parse(from).beginning_of_day..Date.parse(to).end_of_day)

      scope = scope.where(entity_type: filters[:entity_type]) if filters[:entity_type].present?
      scope = scope.where(action: filters[:action]) if filters[:action].present?
      scope = scope.where(user_id: filters[:user_id]) if filters[:user_id].present?
      scope
    end

    def build_csv(scope)
      require 'csv'

      CSV.generate do |out|
        out << %w[created_at user_id user_name action entity_type entity_id ip changed_keys before after]

        # find_each pra streaming — evita carregar 100k rows na memória
        scope.find_each(batch_size: 500) do |log|
          changed_keys = compute_diff_keys(log.before, log.after)
          user_name = ::User.where(id: log.user_id).pick(:name) if log.user_id

          out << [
            log.created_at.iso8601,
            log.user_id,
            user_name,
            log.action,
            log.entity_type,
            log.entity_id,
            log.ip_address,
            changed_keys.join(','),
            sanitized_json(log.before, changed_keys),
            sanitized_json(log.after, changed_keys)
          ]
        end
      end
    end

    def build_filename(account:, from:, to:)
      ts = Time.current.strftime('%Y%m%d-%H%M%S')
      "financial-audit-#{account.id}-#{from}_#{to}-#{ts}.csv"
    end

    # Sobe pro Active Storage. Initializer global prefixa key por
    # `accounts/<id>/` (memory project_active_storage_account_scoping)
    # — bucket no R2 fica naturalmente segregado por tenant.
    def upload_to_storage(content:, filename:, account:)
      # rubocop:disable Rails/ActiveSupportOnLoad
      io = StringIO.new(content)
      ::ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: 'text/csv',
        metadata: {
          account_id: account.id,
          kind: 'audit_export',
          generated_at: Time.current.iso8601
        }
      )
      # rubocop:enable Rails/ActiveSupportOnLoad
    end

    def signed_url_for(blob)
      # rails_blob_url usa Rails Storage routes — funciona com R2/S3 via
      # `service_url` que assina o link com expiração.
      Rails.application.routes.url_helpers.rails_blob_url(
        blob,
        host: ::ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
        expires_in: EXPORT_TTL,
        disposition: 'attachment'
      )
    rescue ArgumentError
      # Fallback: alguns hosts não suportam `expires_in` no helper — usa
      # service_url direto no blob.
      blob.service_url(expires_in: EXPORT_TTL, disposition: 'attachment')
    end

    def sanitized_json(payload, changed_keys)
      return '{}' if payload.blank?
      return '{}' unless payload.is_a?(Hash)

      relevant = payload.slice(*changed_keys.map(&:to_s))
      sanitized = relevant.each_with_object({}) do |(k, v), h|
        h[k] = PII_KEYS_DROP.include?(k.to_s.downcase) ? '<redacted>' : v
      end
      sanitized.to_json
    end

    def compute_diff_keys(before, after)
      return [] if before.blank? && after.blank?
      b = before.is_a?(Hash) ? before : {}
      a = after.is_a?(Hash) ? after : {}
      (b.keys | a.keys).select { |k| b[k] != a[k] }
    end
  end
end
