module Financial
  # Bootstrap automático de Account nova com canon financeiro.
  # Disparado por `after_create_commit` em Account (via engine.rb).
  #
  # Idempotente: roda Financial::Bootstrap::SeedDefaultCategories que usa
  # find_or_create_by. Retry seguro.
  #
  # Em ambiente de testes que use perform_now/perform_later inline, executa
  # síncrono. Em produção, vai pra queue `default` com retry padrão do AR.
  class BootstrapAccountJob < ApplicationJob
    queue_as :default

    # Em caso de erro transiente (deadlock em concurrent account creation),
    # retenta. Erros estruturais (validation) discard — bootstrap falhou,
    # operador resolve manualmente.
    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(account_id)
      account = ::Account.find_by(id: account_id)
      return Rails.logger.warn("[BootstrapAccountJob] Account ##{account_id} not found") if account.nil?

      # Skip se conta já tem categorias (já foi bootstrap'ed ou seed manual)
      existing_count = ::Financial::DreCategory.for_account(account.id).alive.count
      if existing_count.positive?
        Rails.logger.info("[BootstrapAccountJob] Account ##{account_id} already has #{existing_count} categories — skipping bootstrap")
        return
      end

      result = ::Financial::Bootstrap::SeedDefaultCategories.call(account: account)
      if result.success?
        Rails.logger.info(
          "[BootstrapAccountJob] Account ##{account_id} bootstrapped — " \
          "created=#{result[:created]} skipped=#{result[:skipped]} total=#{result[:total]}"
        )
      else
        Rails.logger.error("[BootstrapAccountJob] Account ##{account_id} bootstrap FAILED — #{result.errors.join('; ')}")
      end
    end
  end
end
