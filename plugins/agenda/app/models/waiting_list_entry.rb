class WaitingListEntry < ApplicationRecord
  belongs_to :account
  belongs_to :contact

  VALID_PERIODS = %w[morning afternoon evening].freeze

  validates :period, inclusion: { in: VALID_PERIODS }
  validates :contact_id, uniqueness: { scope: :account_id, message: 'já está na lista de espera' }
end
