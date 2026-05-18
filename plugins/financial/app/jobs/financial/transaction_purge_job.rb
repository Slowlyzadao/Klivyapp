# plugins/financial/app/jobs/financial/transaction_purge_job.rb
#
# Purga definitiva de Transaction soft-deleted após o período de retenção.
# Apaga o blob do payment_proof (comprovante de pagamento) no R2 + destrói record.
#
# Idempotente: se o record já foi destruído ou restaurado, no-op silencioso.

module Financial
  class TransactionPurgeJob < ApplicationJob
    queue_as :financial

    sidekiq_options retry: 3, dead: true

    def perform(transaction_id)
      tx = ::Transaction.where.not(deleted_at: nil).find_by(id: transaction_id)
      return unless tx # já foi destruído manualmente OU restaurado

      tx.payment_proof.purge_later if tx.payment_proof.attached?
      tx.destroy!
      Rails.logger.info("[Financial::TransactionPurgeJob] purged transaction=#{transaction_id}")
    end
  end
end
