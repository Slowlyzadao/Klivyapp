# lib/tasks/sync_patient_transactions.rake
#
# Sincroniza transações históricas do financeiro do paciente (Transaction)
# para o financeiro central (AccountTransaction).
#
# Uso:
#   bundle exec rails financial:sync_patient_transactions
#   bundle exec rails "financial:sync_patient_transactions[account_id]"  # apenas uma conta

namespace :financial do
  desc 'Espelha todas as Transactions de pacientes que ainda não estão no AccountTransaction'
  task :sync_patient_transactions, [:account_id] => :environment do |_t, args|
    puts '[sync] Iniciando sincronização de transações de pacientes...'

    scope = Transaction.active.includes(:patient)
    scope = scope.where(account_id: args[:account_id]) if args[:account_id].present?

    created_count  = 0
    paid_count     = 0
    skipped_count  = 0

    scope.find_each do |tx|
      already_synced = AccountTransaction.exists?(source_transaction_id: tx.id)

      if already_synced
        # Mesmo sincronizado, garante que o status bate (ex: foi pago depois da sync)
        acct_tx = AccountTransaction.find_by(source_transaction_id: tx.id)
        if acct_tx && tx.status_pago? && acct_tx.status != 'recebido'
          Patients::TransactionSyncService.on_paid(tx)
          paid_count += 1
        else
          skipped_count += 1
        end
      else
        # Cria o espelho
        Patients::TransactionSyncService.on_created(tx)
        created_count += 1

        # Se já estava pago, atualiza imediatamente
        if tx.status_pago?
          Patients::TransactionSyncService.on_paid(tx)
          paid_count += 1
        end
      end
    rescue StandardError => e
      puts "[sync][ERROR] transaction_id=#{tx.id}: #{e.message}"
    end

    puts "[sync] Concluído! Criados: #{created_count} | Atualizados (pagamentos): #{paid_count} | Ignorados: #{skipped_count}"
  end
end
