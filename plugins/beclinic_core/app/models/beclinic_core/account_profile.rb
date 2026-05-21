module BeclinicCore
  class AccountProfile < ApplicationRecord
    self.table_name = 'beclinic_account_profiles'
    belongs_to :account
  end
end
