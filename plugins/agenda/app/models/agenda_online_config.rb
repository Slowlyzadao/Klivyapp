class AgendaOnlineConfig < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true, uniqueness: true
  validates :min_lead_time_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :future_limit_days, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  # Default form fields structure
  def self.default_form_fields
    [
      { id: 'first_name', label: 'Nome', type: 'text', required: true, system: true },
      { id: 'last_name', label: 'Sobrenome', type: 'text', required: true, system: true },
      { id: 'cpf', label: 'CPF', type: 'text', required: true, system: true },
      { id: 'phone_number', label: 'Celular', type: 'tel', required: true, system: true },
      { id: 'email', label: 'E-mail', type: 'email', required: true, system: true },
      { id: 'observations', label: 'Observações', type: 'text-long', required: false, system: true }
    ]
  end
end
