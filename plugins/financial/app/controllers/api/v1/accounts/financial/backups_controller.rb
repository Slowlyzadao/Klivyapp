module Api
  module V1
    module Accounts
      module Financial
        # F-32 (versão "lite") — visualização dos dumps que o Easypanel /
        # Postgres já geram. Read-only, sem expor download por padrão
        # (dump contém dados sensíveis — paciente, financeiro, segredos).
        #
        # Diretório configurável via env `FINANCIAL_BACKUP_PATH`.
        # Default `/app/storage/postgres-backups` — caminho do volume
        # persistente do Easypanel (memória do projeto).
        #
        # ADMIN-only. AUDITOR pode ver pra fins de compliance (canon F-32
        # critério "Notifica ADMIN se backup falhar").
        class BackupsController < BaseController
          before_action :require_admin_or_auditor!

          # Heurística: arquivos típicos de pg_dump.
          BACKUP_EXTENSIONS = %w[.sql .sql.gz .dump .tar .tar.gz .backup].freeze

          def index
            local_files = list_local_files
            r2_result = list_r2_files

            # Merge local + R2 por nome do arquivo. Mesmo arquivo nas 2
            # fontes vira UMA linha com sources=[local, r2].
            merged = merge_files(local_files, r2_result[:files])

            render json: {
              data: merged,
              meta: {
                local: {
                  path: backup_path,
                  configured: File.directory?(backup_path),
                  count: local_files.size
                },
                r2: r2_result[:meta],
                total: merged.size,
                oldest_days: merged.last&.dig(:age_days),
                newest_days: merged.first&.dig(:age_days),
                total_size_human: humanize_size(merged.sum { |f| f[:size_bytes].to_i })
              }
            }
          rescue => e
            Rails.logger.error("[BackupsController] erro listando: #{e.class}: #{e.message}")
            render json: { error: 'list_failed', message: e.message }, status: :internal_server_error
          end

          # POST /financial/v2/backups/destroy — apaga um backup específico
          # (local + R2). ADMIN-only. Útil pra limpar dumps antigos ou
          # corrompidos sem esperar o cron de retenção.
          #
          # Validação dura: nome do arquivo precisa bater no pattern
          # `klivy-YYYYMMDD-HHMMSS.sql.gz` pra prevenir path traversal
          # (ex.: `../../etc/passwd`).
          BACKUP_NAME_PATTERN = /\Aklivy-\d{8}-\d{6}\.sql\.gz\z/.freeze

          def destroy
            require_admin_only!
            return if performed?

            name = params[:filename].to_s
            unless name.match?(BACKUP_NAME_PATTERN)
              return render(json: { error: 'invalid_filename' }, status: :bad_request)
            end

            deleted = { local: false, r2: false }
            errors = []

            # Local
            local_path = File.join(backup_path, name)
            if File.file?(local_path)
              begin
                File.delete(local_path)
                deleted[:local] = true
              rescue => e
                errors << "local: #{e.message}"
              end
            end

            # R2
            if ::Financial::Backup::R2Storage.enabled?
              begin
                storage = ::Financial::Backup::R2Storage.new
                key = "#{storage.prefix}#{name}"
                # delete é idempotente em R2 (não-erro se já não existe).
                storage.delete(key)
                deleted[:r2] = true
              rescue => e
                errors << "r2: #{e.message}"
              end
            end

            if deleted[:local] || deleted[:r2]
              render json: { success: true, deleted: deleted, errors: errors }
            else
              render json: {
                success: false,
                error: errors.any? ? errors.join('; ') : 'Arquivo não encontrado em nenhuma fonte.'
              }, status: :not_found
            end
          end

          # POST /financial/v2/backups/run — dispara CreateBackup imediatamente.
          # Útil antes de uma migration arriscada ou pra testar a infra.
          # Executa SÍNCRONO (não enfileira) pra o usuário ter retorno imediato
          # do sucesso/falha. Backups são curtos (segundos a poucos minutos).
          def run
            require_admin_only!
            return if performed?

            result = ::Financial::CreateBackup.call
            if result.success?
              render json: {
                success: true,
                file: File.basename(result.path),
                size_bytes: result.size_bytes,
                duration_seconds: result.duration_seconds,
                pruned_count_local: result.pruned_count_local,
                pruned_count_r2: result.pruned_count_r2,
                r2_uploaded: result.r2_uploaded,
                r2_key: result.r2_key,
                r2_error: result.r2_error
              }
            else
              render json: { success: false, error: result.error }, status: :unprocessable_entity
            end
          end

          private

          def list_local_files
            return [] unless File.directory?(backup_path)
            Dir.children(backup_path).filter_map do |entry|
              full = File.join(backup_path, entry)
              next unless File.file?(full)
              next unless backup_file?(entry)
              stat = File.stat(full)
              {
                name: entry,
                size_bytes: stat.size,
                modified_at: stat.mtime
              }
            end
          end

          def list_r2_files
            unless ::Financial::Backup::R2Storage.enabled?
              return { files: [], meta: { configured: false, count: 0 } }
            end

            objects = ::Financial::Backup::R2Storage.new.list
            files = objects.map do |obj|
              {
                name: obj[:name],
                size_bytes: obj[:size_bytes],
                modified_at: Time.parse(obj[:last_modified]),
                r2_key: obj[:key]
              }
            end
            {
              files: files,
              meta: {
                configured: true,
                bucket: ::Financial::Backup::R2Storage.bucket_name,
                count: files.size
              }
            }
          rescue => e
            Rails.logger.warn("[BackupsController] R2 list falhou: #{e.class}: #{e.message}")
            { files: [], meta: { configured: true, count: 0, error: e.message } }
          end

          # Combina arquivos locais + R2 por nome. Cada item resultante
          # tem `sources: ['local', 'r2']` indicando onde está armazenado.
          # Tamanho prevalece o local (que é o que efetivamente foi
          # gerado — R2 é cópia).
          def merge_files(locals, r2s)
            by_name = {}
            locals.each do |f|
              by_name[f[:name]] = serialize_file(f, sources: ['local'])
            end
            r2s.each do |f|
              if by_name[f[:name]]
                by_name[f[:name]][:sources] << 'r2'
                by_name[f[:name]][:r2_key] = f[:r2_key]
              else
                by_name[f[:name]] = serialize_file(f, sources: ['r2'], extra: { r2_key: f[:r2_key] })
              end
            end
            by_name.values.sort_by { |f| -Time.parse(f[:modified_at]).to_i }
          end

          def serialize_file(file, sources:, extra: {})
            {
              name: file[:name],
              size_bytes: file[:size_bytes],
              size_human: humanize_size(file[:size_bytes]),
              modified_at: file[:modified_at].iso8601,
              age_days: ((Time.current - file[:modified_at]) / 1.day).floor,
              sources: sources
            }.merge(extra)
          end

          # Mesmo default do service — Rails.root local; em prod o env
          # FINANCIAL_BACKUP_PATH aponta pro volume Easypanel.
          def backup_path
            ENV['FINANCIAL_BACKUP_PATH'].presence ||
              Rails.root.join('storage/postgres-backups').to_s
          end

          # "Backup agora" é mais sensível que listar — só ADMIN dispara.
          def require_admin_only!
            render(json: { error: 'forbidden' }, status: :forbidden) \
              unless user_has_any_role?(%w[ADMIN])
          end

          def backup_file?(name)
            BACKUP_EXTENSIONS.any? { |ext| name.downcase.end_with?(ext) }
          end

          def humanize_size(bytes)
            return '0 B' if bytes.zero?
            units = %w[B KB MB GB TB]
            exp = (Math.log(bytes) / Math.log(1024)).to_i.clamp(0, units.size - 1)
            value = bytes.to_f / (1024**exp)
            format('%.1f %s', value, units[exp])
          end

          def require_admin_or_auditor!
            render(json: { error: 'forbidden' }, status: :forbidden) \
              unless user_has_any_role?(%w[ADMIN AUDITOR])
          end
        end
      end
    end
  end
end
