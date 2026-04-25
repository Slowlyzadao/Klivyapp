# app/services/patients/transaction_sync_service.rb
#
# SERVICE: TransactionSyncService
#
# Propósito: Ponte entre o financeiro do PACIENTE (Transaction) e o financeiro
#   CENTRAL da clínica (AccountTransaction). Garante idempotência via
#   source_transaction_id (UNIQUE no banco).
#
# Eventos cobertos:
#   - :created  → cria AccountTransaction pendente/a_receber
#   - :paid     → muda status para "recebido" e preenche received_at
#   - :cancelled → soft_delete na AccountTransaction espelhada
#   - :refunded  → cria AccountTransaction de estorno (saida)

module Patients
  class TransactionSyncService
    def self.on_created(transaction)
      new(transaction).sync_created
    end

    def self.on_paid(transaction, bank_account_id: nil)
      new(transaction).sync_paid(bank_account_id: bank_account_id)
    end

    def self.on_cancelled(transaction)
      new(transaction).sync_cancelled
    end

    def self.on_refunded(transaction, refund_transaction)
      new(transaction).sync_refunded(refund_transaction)
    end

    def initialize(transaction)
      @tx = transaction
    end

    # ── Criação: espelha como "entrada pendente" no financeiro central ─────────
    def sync_created
      return if AccountTransaction.exists?(source_transaction_id: @tx.id)
      return if @tx.transaction_type_reembolso? # reembolsos são tratados em sync_refunded

      AccountTransaction.create!(
        account_id:            @tx.account_id,
        patient_id:            @tx.patient_id,
        registered_by_id:      @tx.registered_by_id,
        source_transaction_id: @tx.id,
        entry_type:            'entrada',
        amount:                @tx.amount,
        payment_method:        map_payment_method(@tx.payment_method),
        status:                'pendente',
        origin:                'orcamento',
        due_date:              @tx.due_date,
        competence_date:       @tx.due_date&.beginning_of_month || Date.today.beginning_of_month,
        description:           @tx.description,
        notes:                 @tx.notes,
        metadata: {
          transaction_id:        @tx.id,
          financial_estimate_id: @tx.financial_estimate_id,
          installment_number:    @tx.installment_number,
          total_installments:    @tx.total_installments
        }
      )
    rescue ActiveRecord::RecordNotUnique
      # Idempotência: corrida de condição — já existe, tudo bem
    end

    # ── Pagamento: atualiza o espelho para "recebido" ─────────────────────────
    def sync_paid(bank_account_id: nil)
      acct_tx = find_mirror
      return unless acct_tx

      updates = {
        status:         'recebido',
        received_at:    @tx.paid_at || Date.today,
        payment_method: map_payment_method(@tx.payment_method)
      }
      updates[:bank_account_id] = bank_account_id if bank_account_id.present?

      acct_tx.update!(updates)
    end

    # ── Cancelamento: soft-delete no espelho ──────────────────────────────────
    def sync_cancelled
      acct_tx = find_mirror
      acct_tx&.soft_delete!
    end

    # ── Reembolso: cria uma saída no financeiro central ───────────────────────
    def sync_refunded(refund_tx)
      return if AccountTransaction.exists?(source_transaction_id: refund_tx.id)

      AccountTransaction.create!(
        account_id:            refund_tx.account_id,
        patient_id:            refund_tx.patient_id,
        registered_by_id:      refund_tx.registered_by_id,
        source_transaction_id: refund_tx.id,
        entry_type:            'saida',
        amount:                refund_tx.amount,
        payment_method:        map_payment_method(refund_tx.payment_method),
        status:                'pago',
        origin:                'manual',
        paid_at:               refund_tx.paid_at || Date.today,
        competence_date:       Date.today.beginning_of_month,
        description:           refund_tx.description,
        metadata: {
          refund_for_transaction_id: @tx.id,
          transaction_id:            refund_tx.id
        }
      )
    rescue ActiveRecord::RecordNotUnique
      # Idempotência
    end

    private

    def find_mirror
      AccountTransaction.find_by(source_transaction_id: @tx.id)
    end

    # Mapeamento: Transaction#payment_method → AccountTransaction#payment_method
    # AccountTransaction não tem 'outros' — mapeia para nil (campo opcional).
    def map_payment_method(method)
      return nil if method.to_s == 'outros'

      method.to_s.presence
    end
  end
end
