module Financial
  # Solicitação de anonimização LGPD — canon F-33 §parte 2.
  #
  # Workflow:
  #   pending → approved → executed
  #         \→ rejected
  #
  # Cancellation: pode acontecer em pending (paciente desiste) ou
  # approved (ADMIN reverte antes de executar). Após `executed` é
  # irreversível (hash já aplicado, dados originais perdidos).
  class LgpdRequest < ApplicationRecord
    self.table_name = 'financial_lgpd_requests'

    STATUSES = %w[pending approved executed rejected cancelled].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :patient, class_name: '::Patient'
    belongs_to :approved_by,  class_name: '::User', optional: true
    belongs_to :executed_by,  class_name: '::User', optional: true
    belongs_to :rejected_by,  class_name: '::User', optional: true

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :requested_at, presence: true

    scope :pending,    -> { where(status: 'pending') }
    scope :approved,   -> { where(status: 'approved') }
    scope :executed,   -> { where(status: 'executed') }
    scope :rejected,   -> { where(status: 'rejected') }
    scope :cancelled,  -> { where(status: 'cancelled') }
    scope :open,       -> { where(status: %w[pending approved]) }

    def pending?    = status == 'pending'
    def approved?   = status == 'approved'
    def executed?   = status == 'executed'
    def rejected?   = status == 'rejected'
    def cancelled?  = status == 'cancelled'

    # Solicitações abertas podem ser canceladas; executadas não.
    def cancelable?
      pending? || approved?
    end

    # Só requests aprovadas (não executadas) podem ser executadas.
    def executable?
      approved?
    end
  end
end
