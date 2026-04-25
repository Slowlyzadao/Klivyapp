module Billing
  class Customer < ApplicationRecord
    self.table_name = 'billing_customers'

    validates :name, :email, presence: true
    validates :email, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :cpf_cnpj, presence: true
  end
end
