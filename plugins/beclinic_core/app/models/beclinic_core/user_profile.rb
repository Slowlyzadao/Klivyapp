module BeclinicCore
  class UserProfile < ApplicationRecord
    self.table_name = 'beclinic_user_profiles'
    belongs_to :user
    # `account_id` é a fonte de verdade do link público `/agenda/:agenda_public_id`.
    # Migration `20260514100001_add_account_to_beclinic_user_profiles` torna NOT NULL.
    belongs_to :account
  end
end
