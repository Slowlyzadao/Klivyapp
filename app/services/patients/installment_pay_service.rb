# app/services/patients/installment_pay_service.rb
#
# SERVICE: InstallmentPayService
#
# Propósito: BAIXA DUPLA — marca a transação/parcela como paga no paciente
#   E injeta uma entrada no CashEntry (caixa geral da clínica).
#   É o ponto de integração entre o financeiro do paciente e o caixa geral.
#
# Uso:
#   result = Patients::InstallmentPayService.call(
#     transaction: transaction,
#     actor: current_user,
#     payment_method: 'pix',     # pode diferir do método original
#     paid_at: Date.today        # data do pagamento (opcional, default: hoje)
#   )
#   result.success?      # true/false
#   result.transaction   # Transaction atualizada
#   result.cash_entry    # CashEntry criado
#   result.error         # mensagem de erro se falhou

module Patients
  class InstallmentPayService
    Result = Struct.new(:success?, :transaction, :cash_entry, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(transaction:, actor:, payment_method: nil, paid_at: nil, bank_account_id: nil)
      @transaction = transaction
      @actor = actor
      @payment_method = payment_method || transaction.payment_method
      @paid_at = paid_at || Date.today
      @bank_account_id = bank_account_id
    end

    def call
      # Guard: apenas pendentes podem ser baixadas
      unless @transaction.status_pendente? || @transaction.status_vencido?
        return Result.new(
          success?: false,
          transaction: @transaction,
          cash_entry: nil,
          error: "Transação com status '#{@transaction.status}' não pode ser baixada"
        )
      end

      ActiveRecord::Base.transaction do
        # 1. Cria o CashEntry (entrada no caixa geral)
        cash_entry = create_cash_entry

        # 2. Marca a transação como paga + vincula ao CashEntry
        @transaction.update!(
          status: 'pago',
          paid_at: @paid_at,
          payment_method: @payment_method,
          cash_entry_id: cash_entry.id
        )

        # 3. Se for parcelada, atualiza a installment correspondente
        update_installment(cash_entry) if @transaction.parcelado?

        # 4. Sync explícito com financeiro central (garante atualização mesmo em
        #    contextos com transações aninhadas onde after_commit não dispara imediatamente)
        ::Patients::TransactionSyncService.on_paid(@transaction, bank_account_id: @bank_account_id)

        # 5. Dispara job de timeline
        PatientTimelineEventJob.perform_later(
          patient_id: @transaction.patient_id,
          event_type: 'payment',
          label: "Pagamento recebido: R$ #{@transaction.amount} (#{@payment_method})",
          actor_id: @actor.id,
          actor: @actor.name,
          reference_id: @transaction.id,
          reference_type: 'Transaction'
        )

        Result.new(
          success?: true,
          transaction: @transaction.reload,
          cash_entry: cash_entry,
          error: nil
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, transaction: @transaction, cash_entry: nil, error: e.message)
    rescue StandardError => e
      Rails.logger.error("[InstallmentPayService] Erro: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      Result.new(success?: false, transaction: @transaction, cash_entry: nil, error: e.message)
    end

    private

    def create_cash_entry
      mapped_method = case @payment_method.to_s
                      when 'cartao_credito' then 'credit_card'
                      when 'cartao_debito' then 'debit_card'
                      when 'dinheiro' then 'cash'
                      when 'transferencia' then 'bank_transfer'
                      when 'outros' then 'others'
                      else @payment_method.to_s
                      end

      CashEntry.create!(
        account_id: @transaction.account_id,
        patient_id: @transaction.patient_id,
        entry_type: 'income',
        amount: @transaction.amount,
        payment_method: mapped_method,
        description: @transaction.description || "Baixa: Paciente ##{@transaction.patient_id}",
        entry_date: @paid_at,
        registered_by_id: @actor.id,
        source_type: 'Transaction',
        source_id: @transaction.id,
        metadata: {
          transaction_id: @transaction.id,
          installment_number: @transaction.installment_number,
          total_installments: @transaction.total_installments,
          financial_estimate_id: @transaction.financial_estimate_id
        }
      )
    end

    def update_installment(cash_entry)
      installment = Installment.active.find_by(
        transaction_id: @transaction.id,
        number: @transaction.installment_number
      )

      return unless installment

      installment.update!(
        status: 'pago',
        paid_at: @paid_at,
        payment_method: @payment_method,
        cash_entry_id: cash_entry.id,
        registered_by_id: @actor.id
      )
    end
  end
end
