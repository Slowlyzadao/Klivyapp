require Rails.root.join('lib/redis/config')

schedule_file = 'config/schedule.yml'

# Propaga Current.account entre thread do request e thread do worker Sidekiq.
#
# Por que: o initializer active_storage_account_scoping.rb prefixa o key dos
# blobs com `accounts/<id>/` quando Current.account está setado. Jobs Sidekiq
# rodam em threads novas que não herdam Current (thread_mattr_accessor é
# per-thread) — então qualquer `.attach` ou `create_and_upload!` dentro de um
# job vinha unscoped, caindo na raiz do bucket R2.
#
# Comportamento:
#   - Client middleware (no enqueue): serializa Current.account&.id em
#     job['current_account_id'] se houver context. Idempotente: não sobrescreve.
#   - Server middleware (no perform): restaura Current.account a partir do
#     payload e limpa no ensure (preservando valor anterior da thread).
#
# Edge cases cobertos:
#   - Enqueue sem account (cron, console, system jobs) → payload sem
#     current_account_id → server middleware é no-op
#   - Account deletada entre enqueue e perform → find_by retorna nil → no-op
#   - Jobs antigos enfileirados antes do deploy → sem a chave no payload → no-op
class ChatwootCurrentAccountClientMiddleware
  def call(_worker_class, job, _queue, _redis_pool)
    account_id = Current.account&.id
    job['current_account_id'] = account_id if account_id && !job.key?('current_account_id')
    yield
  end
end

class ChatwootCurrentAccountServerMiddleware
  def call(_worker, job, _queue)
    account_id = job['current_account_id']
    return yield unless account_id

    account = Account.find_by(id: account_id)
    return yield unless account

    previous = Current.account
    Current.account = account
    begin
      yield
    ensure
      Current.account = previous
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = Redis::Config.app
  config.client_middleware do |chain|
    chain.add ChatwootCurrentAccountClientMiddleware
  end
end

# Logs whenever a job is pulled off Redis for execution.
class ChatwootDequeuedLogger
  def call(_worker, job, queue)
    payload = job['args'].first
    Sidekiq.logger.info("Dequeued #{job['wrapped']} #{payload['job_id']} from #{queue}")
    yield
  end
end

Sidekiq.configure_server do |config|
  config.redis = Redis::Config.app

  config.client_middleware do |chain|
    chain.add ChatwootCurrentAccountClientMiddleware
  end

  config.server_middleware do |chain|
    chain.add ChatwootCurrentAccountServerMiddleware
  end

  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_SIDEKIQ_DEQUEUE_LOGGER', false))
    config.server_middleware do |chain|
      chain.add ChatwootDequeuedLogger
    end
  end

  # skip the default start stop logging
  if Rails.env.production?
    config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    config[:skip_default_job_logging] = true
    config.logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'info').upcase.to_s)
  end
end

# https://github.com/ondrejbartas/sidekiq-cron
Rails.application.reloader.to_prepare do
  Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file) if File.exist?(schedule_file) && Sidekiq.server?
end
