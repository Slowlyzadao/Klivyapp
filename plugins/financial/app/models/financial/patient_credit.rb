module Financial
  # Ledger de crédito do paciente (saldo a favor).
  # Canon glossário: "Crédito do paciente — saldo a favor. Vem de estorno sem
  # devolução, pré-pagamento ou pagamento maior que a parcela. Pode ser abatido
  # em parcela futura ou sacado em dinheiro."
  #
  # Saldo do paciente = SUM(amount_cents) onde amount_cents > 0 (créditos)
  #                   + SUM(amount_cents) onde amount_cents < 0 (abatimentos/saques)
  #                   = SUM(amount_cents)
  class PatientCredit < ApplicationRecord
    self.table_name = 'financial_patient_credits'

    ORIGINS = %w[
      estorno
      pre_pagamento
      pagamento_excedente
      abatimento_parcela
      saque_dinheiro
      ajuste_manual
    ].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :patient, class_name: '::Patient'
    belongs_to :registered_by, class_name: '::User', optional: true
    belongs_to :origin_record, polymorphic: true, optional: true,
               foreign_type: :origin_type, foreign_key: :origin_id

    money_attribute :amount_cents, as: :amount

    validates :origin, presence: true, inclusion: { in: ORIGINS }
    validates :amount_cents, presence: true,
              numericality: { other_than: 0, only_integer: true }
    validates :occurred_at, presence: true

    scope :for_patient, ->(patient_id) { where(patient_id: patient_id) }
    scope :credits, -> { where('amount_cents > 0') }
    scope :debits,  -> { where('amount_cents < 0') }

    # Saldo atual de um paciente em centavos.
    def self.balance_cents_for(account_id:, patient_id:)
      for_account(account_id).for_patient(patient_id).sum(:amount_cents)
    end

    def self.balance_for(account_id:, patient_id:)
      BigDecimal(balance_cents_for(account_id: account_id, patient_id: patient_id)) / 100
    end
  end
end
