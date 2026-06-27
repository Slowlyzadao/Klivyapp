module Agenda
  # Bootstrap automático de AgendaServices padrão pra Account nova.
  # Espelha o Financial::BootstrapAccountJob — mesmo padrão, dados diferentes.
  #
  # Disparado por `after_create_commit` em Account (via engine.rb).
  # Idempotente — rodar 2x não duplica.
  class BootstrapAccountJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(account_id)
      account = ::Account.find_by(id: account_id)
      return Rails.logger.warn("[Agenda::BootstrapAccountJob] Account ##{account_id} not found") if account.nil?

      # NÃO fazer early return — o service `SeedDefaultServices` é
      # idempotente por external_id (`canon:endodontia`) + name. Em contas
      # que já têm serviços legacy (ex: do db/seeds/treatments.rb antigo:
      # "Avaliação", "Profilaxia"), o service ADICIONA os 10 canon sem
      # apagar/duplicar — operador fica com legacy + canon coexistindo
      # (decisão informada: canon DRE × AgendaServices deve estar simétrico).
      result = ::Agenda::Bootstrap::SeedDefaultServices.call(account: account)
      if result.success?
        Rails.logger.info(
          "[Agenda::BootstrapAccountJob] Account ##{account_id} bootstrapped — " \
          "created=#{result.created} skipped=#{result.skipped}"
        )
      else
        Rails.logger.error("[Agenda::BootstrapAccountJob] Account ##{account_id} bootstrap FAILED — #{result.errors.join('; ')}")
      end
    end
  end
end
