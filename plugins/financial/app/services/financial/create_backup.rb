module Financial
  # Cria dump comprimido do banco via `pg_dump`, espelha pra R2 (se
  # configurado) e aplica retenções separadas — canon F-32 §retenção.
  #
  # Estratégia "Local + R2 mirror":
  #   1. pg_dump → arquivo local (FINANCIAL_BACKUP_PATH ou Rails.root)
  #   2. Se R2 estiver configurado (R2_* envs), faz upload
  #   3. Aplica retenção LOCAL (default 7 dias — local é só staging)
  #   4. Aplica retenção R2 (default 30 dias — canon)
  #
  # Se R2 falhar, o dump local fica preservado (defense in depth).
  # Se R2 não estiver configurado, vira backup só-local (compatível com
  # quem ainda não tem R2).
  #
  # Retorna Struct com :success?, :path, :size_bytes, :duration_seconds,
  # :pruned_count_local, :pruned_count_r2, :r2_uploaded, :r2_key,
  # :r2_error, :error.
  class CreateBackup
    Result = Struct.new(:success?, :path, :size_bytes, :duration_seconds,
                        :pruned_count_local, :pruned_count_r2,
                        :r2_uploaded, :r2_key, :r2_error, :error,
                        keyword_init: true)

    RETENTION_DAYS_LOCAL = 7
    RETENTION_DAYS_R2 = 30
    DUMP_PREFIX = 'klivy'.freeze

    attr_reader :destination_path, :local_retention_days, :r2_retention_days

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(destination_path: nil, local_retention_days: RETENTION_DAYS_LOCAL,
                   r2_retention_days: RETENTION_DAYS_R2)
      @destination_path = destination_path || default_path
      @local_retention_days = local_retention_days
      @r2_retention_days = r2_retention_days
    end

    def call
      ensure_dir_exists!
      filename = "#{DUMP_PREFIX}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.sql.gz"
      path = File.join(destination_path, filename)
      started = Time.current

      ok = run_pg_dump(path)
      unless ok
        cleanup_partial(path)
        return Result.new(
          success?: false,
          error: @last_error.presence || 'pg_dump falhou — confira logs.'
        )
      end

      size = File.size(path)
      duration = (Time.current - started).round(2)

      # Mirror pra R2. Falha aqui é WARN (não erro fatal — o dump local
      # tá íntegro). Logamos pro Sentry/AppSignal pegarem.
      r2_uploaded = false
      r2_key = nil
      r2_error = nil
      if Financial::Backup::R2Storage.enabled?
        begin
          upload_result = Financial::Backup::R2Storage.new.upload(path)
          r2_uploaded = true
          r2_key = upload_result[:key]
        rescue => e
          r2_error = "#{e.class}: #{e.message}"
          Rails.logger.warn("[Financial::CreateBackup] R2 upload falhou: #{r2_error}")
        end
      end

      pruned_local = prune_old_local_backups
      pruned_r2 = prune_old_r2_backups

      Rails.logger.info(
        "[Financial::CreateBackup] dump=#{path} size=#{size}B " \
        "duration=#{duration}s pruned_local=#{pruned_local} " \
        "r2_uploaded=#{r2_uploaded} pruned_r2=#{pruned_r2}"
      )

      Result.new(
        success?: true,
        path: path, size_bytes: size, duration_seconds: duration,
        pruned_count_local: pruned_local, pruned_count_r2: pruned_r2,
        r2_uploaded: r2_uploaded, r2_key: r2_key, r2_error: r2_error
      )
    rescue => e
      Rails.logger.error("[Financial::CreateBackup] erro: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      Result.new(success?: false, error: "#{e.class}: #{e.message}")
    end

    private

    # Default: Rails.root/storage/postgres-backups. Funciona em qualquer
    # ambiente sem heurística frágil. Em produção Easypanel, override
    # explícito via env FINANCIAL_BACKUP_PATH=/app/storage/postgres-backups
    # (apontando pro volume klivy_storage).
    def default_path
      ENV['FINANCIAL_BACKUP_PATH'].presence ||
        Rails.root.join('storage/postgres-backups').to_s
    end

    def ensure_dir_exists!
      FileUtils.mkdir_p(destination_path)
    end

    # Tamanho mínimo plausível (mesmo um banco vazio com schema gera dezenas
    # de KB). Abaixo disso é certeza de erro silencioso (pg_dump cuspiu vazio).
    MIN_DUMP_SIZE = 1024

    def run_pg_dump(output_path)
      env = build_pg_env
      raise 'host do banco não resolvido (DATABASE_URL ou config/database.yml + .env)' if env['PGHOST'].blank?

      # `set -o pipefail` propaga erro de qualquer estágio do pipe — sem
      # isso, gzip de stream vazio retorna 0 e mascara falha do pg_dump.
      # `--clean --if-exists` permite restaurar em DB existente sem conflito.
      # `--no-owner --no-privileges` pula GRANT/OWNER pra portabilidade
      # entre ambientes (dev ↔ prod usam usuários diferentes).
      stderr_log = Tempfile.new('pg_dump_stderr')
      cmd = "set -o pipefail; pg_dump --no-owner --no-privileges --clean --if-exists 2>#{Shellwords.escape(stderr_log.path)} | gzip -9 > #{Shellwords.escape(output_path)}"
      ok = system(env, 'bash', '-c', cmd)

      if !ok || File.size(output_path).to_i < MIN_DUMP_SIZE
        err = File.read(stderr_log.path).to_s.lines.last(8).join.strip
        Rails.logger.error("[Financial::CreateBackup] pg_dump stderr: #{err}")
        @last_error = err.presence || "pg_dump produziu arquivo de #{File.size(output_path)} bytes (vazio)"
        return false
      end
      true
    ensure
      stderr_log&.close
      stderr_log&.unlink
    end

    # Resolve credenciais do banco em ordem:
    # 1) ENV['DATABASE_URL'] (formato `postgres://user:pass@host:port/db`)
    # 2) ActiveRecord::Base.connection_db_config — config já mesclada do
    #    Rails (database.yml + .env Chatwoot-style: POSTGRES_HOST etc.)
    #
    # Passa via variáveis PG* (não como argumento) pra senha não aparecer
    # em `ps`/process list.
    def build_pg_env
      if ENV['DATABASE_URL'].present?
        uri = URI.parse(ENV['DATABASE_URL'])
        return {
          'PGHOST'     => uri.host,
          'PGPORT'     => (uri.port || 5432).to_s,
          'PGUSER'     => CGI.unescape(uri.user.to_s),
          'PGPASSWORD' => CGI.unescape(uri.password.to_s),
          'PGDATABASE' => uri.path.to_s.delete_prefix('/')
        }
      end

      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      {
        'PGHOST'     => cfg[:host].to_s,
        'PGPORT'     => (cfg[:port] || 5432).to_s,
        'PGUSER'     => cfg[:username].to_s,
        'PGPASSWORD' => cfg[:password].to_s,
        'PGDATABASE' => cfg[:database].to_s
      }
    end

    def cleanup_partial(path)
      File.delete(path) if File.exist?(path) && File.size(path) < MIN_DUMP_SIZE
    rescue Errno::ENOENT
      # já removido — ignora
    end

    # Apaga dumps locais com prefixo `klivy-` mais antigos que
    # `local_retention_days` (default 7d — local é staging temporário).
    # Não toca em outros arquivos (segurança caso o usuário ponte outras
    # coisas no diretório).
    def prune_old_local_backups
      return 0 unless File.directory?(destination_path)
      cutoff = local_retention_days.days.ago
      count = 0
      Dir.children(destination_path).each do |entry|
        next unless entry.start_with?(DUMP_PREFIX) && entry.end_with?('.sql.gz')
        full = File.join(destination_path, entry)
        next unless File.file?(full)
        next if File.mtime(full) >= cutoff
        File.delete(full)
        count += 1
      end
      count
    end

    # Apaga objetos R2 com prefixo do bucket mais antigos que
    # `r2_retention_days` (default 30d — canon F-32). No-op se R2 não
    # configurado.
    def prune_old_r2_backups
      return 0 unless Financial::Backup::R2Storage.enabled?
      Financial::Backup::R2Storage.new.prune(retention_days: r2_retention_days)
    rescue => e
      Rails.logger.warn("[Financial::CreateBackup] R2 prune falhou: #{e.class}: #{e.message}")
      0
    end
  end
end
