class AgendaCustomAttribute < ApplicationRecord
  belongs_to :account

  validates :name, presence: true
  validates :field_type, presence: true, inclusion: { in: %w[text textarea select date phone cpf rg] }

  scope :ordered, -> { order(position: :asc) }
end
